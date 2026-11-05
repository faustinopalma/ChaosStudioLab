using Azure.Core;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Demo.Api.Contracts;
using Demo.Api.Data;
using Demo.Api.Security;
using Demo.Api.Services;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Authentication;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);
builder.Logging.AddFilter("Npgsql", LogLevel.Warning);

if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    builder.Services.AddOpenTelemetry().UseAzureMonitor();
}

builder.Services.AddAuthentication("Diagnostics")
    .AddScheme<AuthenticationSchemeOptions, DiagnosticsTokenHandler>("Diagnostics", _ => { });
builder.Services.AddAuthorization();
builder.Services.AddSingleton<TokenCredential>(_ => new DefaultAzureCredential());
builder.Services.AddSingleton<NpgsqlDataSource>(services =>
{
    var configuration = services.GetRequiredService<IConfiguration>();
    var logger = services.GetRequiredService<ILoggerFactory>()
        .CreateLogger("PostgreSqlDataSource");
    var connectionString = configuration.GetConnectionString("Postgres");
    if (string.IsNullOrWhiteSpace(connectionString))
    {
        throw new InvalidOperationException("ConnectionStrings:Postgres is required.");
    }

    var connection = new NpgsqlConnectionStringBuilder(connectionString)
    {
        SslMode = SslMode.VerifyFull,
        Timeout = 3,
        CommandTimeout = 3,
        KeepAlive = 30,
        MinPoolSize = DatabaseWarmupService.PrefilledConnections,
        MaxPoolSize = 50
    };
    var dataSource = new NpgsqlDataSourceBuilder(connection.ConnectionString);
    dataSource.UseLoggerFactory(services.GetRequiredService<ILoggerFactory>());
    dataSource.UseSslClientAuthenticationOptionsCallback(options =>
    {
        options.CertificateRevocationCheckMode = X509RevocationMode.Online;
        options.CertificateChainPolicy = PostgresTlsPolicy.CreateChainPolicy();
    });

    if (!string.Equals(
            configuration["Postgres:Authentication"],
            "Password",
            StringComparison.OrdinalIgnoreCase))
    {
        var credential = services.GetRequiredService<TokenCredential>();
        dataSource.UsePeriodicPasswordProvider(
            async (_, cancellationToken) =>
            {
                var token = await credential.GetTokenAsync(
                    new TokenRequestContext(
                        ["https://ossrdbms-aad.database.windows.net/.default"]),
                    cancellationToken);
                return token.Token;
            },
            TimeSpan.FromMinutes(50),
            TimeSpan.FromSeconds(5));
    }
    else
    {
        logger.LogWarning(
            "PostgreSQL password authentication is enabled; use only for isolated local development.");
    }

    return dataSource.Build();
});
builder.Services.AddSingleton<IOrderRepository, NpgsqlOrderRepository>();
builder.Services.AddSingleton<OrderService>();
builder.Services.AddSingleton<DatabaseHealthProbe>();
builder.Services.AddSingleton<DatabaseOpenDiagnostics>();
builder.Services.AddHostedService<DatabaseWarmupService>();

var app = builder.Build();
var processStartedAtUtc = new DateTimeOffset(
    System.Diagnostics.Process.GetCurrentProcess().StartTime.ToUniversalTime()).ToString("O");
app.Use(async (context, next) =>
{
    context.Response.Headers["X-Lab-Instance-Id"] = ReplicaId();
    context.Response.Headers["X-Lab-Process-Id"] = Environment.ProcessId.ToString();
    context.Response.Headers["X-Lab-Process-Start-Utc"] = processStartedAtUtc;
    System.Diagnostics.Activity.Current?.SetTag("app.instance.id", ReplicaId());
    await next(context);
});
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/health/live", () => Results.Ok(new
{
    status = "live",
    instanceId = ReplicaId(),
    replicaId = ReplicaId(),
    processId = Environment.ProcessId,
    processStartedAtUtc,
    revision = Revision()
}));

app.MapGet("/health/ready", async (
    DatabaseHealthProbe database,
    HttpContext context) =>
{
    var db = await database.CheckAsync(context.RequestAborted);
    var readyResponse = new ReadinessResponse(
        db.Healthy ? "ready" : "not-ready",
        db.Healthy ? null : $"database {db.Status}",
        ReplicaId(),
        Revision(),
        TraceId(context));
    return db.Healthy
        ? Results.Ok(readyResponse)
        : Results.Json(readyResponse, statusCode: StatusCodes.Status503ServiceUnavailable);
});

app.MapGet("/diagnostics/db-open", async (
    DatabaseOpenDiagnostics diagnostics,
    HttpContext context) => Results.Ok(new
{
    instanceId = ReplicaId(),
    processId = Environment.ProcessId,
    processStartedAtUtc,
    revision = Revision(),
    stages = await diagnostics.RunAsync(context.RequestAborted)
})).RequireAuthorization();

app.MapGet("/health/dependencies", async (
    DatabaseHealthProbe database,
    HttpContext context) =>
{
    var result = await database.CheckAsync(context.RequestAborted);
    var response = new
    {
        status = result.Healthy ? "healthy" : "degraded",
        dependencies = new { postgresql = result.Status },
        replicaId = ReplicaId(),
        revision = Revision(),
        traceId = TraceId(context)
    };

    return result.Healthy
        ? Results.Ok(response)
        : Results.Json(response, statusCode: StatusCodes.Status503ServiceUnavailable);
}).RequireAuthorization();

app.MapPost("/api/orders", async (
    CreateOrderRequest? request,
    OrderService orders,
    HttpContext context,
    ILoggerFactory loggerFactory) =>
{
    if (!OrderService.TryValidate(request, out var validated, out var error))
    {
        return Results.ValidationProblem(
            new Dictionary<string, string[]> { ["request"] = [error] });
    }

    var operationId = validated!.OperationId;
    var runId = context.Request.Headers["X-Run-Id"].FirstOrDefault();
    using var scope = loggerFactory.CreateLogger("Orders").BeginScope(
        new Dictionary<string, object?>
        {
            ["OperationId"] = operationId,
            ["RunId"] = runId,
            ["ReplicaId"] = ReplicaId(),
            ["TraceId"] = TraceId(context)
        });

    try
    {
        var result = await orders.CreateAsync(validated, context.RequestAborted);
        var response = ToResponse(result.Order, result.Replayed, runId, context);
        return result.Replayed
            ? Results.Ok(response)
            : Results.Created($"/api/orders/{operationId}", response);
    }
    catch (OrderConflictException)
    {
        return Results.Conflict(new
        {
            error = "operation_id_conflict",
            operationId,
            traceId = TraceId(context)
        });
    }
    catch (DatabaseDeadlineExceededException exception)
    {
        loggerFactory.CreateLogger("Orders").LogWarning(
            exception,
            "Order operation exceeded its request deadline.");
        return Results.Json(
            new { error = "database_deadline_exceeded", operationId, traceId = TraceId(context) },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (DatabaseOperationUnavailableException exception)
    {
        loggerFactory.CreateLogger("Orders").LogError(
            exception,
            "Database retries were exhausted for order {OperationId}; {ExceptionType}: {ExceptionMessage}",
            operationId,
            exception.InnerException?.GetType().FullName,
            exception.InnerException?.Message);
        return Results.Json(
            new { error = "database_unavailable", operationId, traceId = TraceId(context) },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (NpgsqlException exception)
    {
        loggerFactory.CreateLogger("Orders").LogError(
            exception,
            "Database operation failed for order {OperationId}.",
            operationId);
        return Results.Json(
            new { error = "database_unavailable", operationId, traceId = TraceId(context) },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("CreateOrder")
.RequireAuthorization();

app.MapGet("/api/orders/{operationId:guid}", async (
    Guid operationId,
    OrderService orders,
    HttpContext context,
    ILoggerFactory loggerFactory) =>
{
    try
    {
        var order = await orders.GetAsync(operationId, context.RequestAborted);
        return order is null
            ? Results.NotFound(new { operationId, traceId = TraceId(context) })
            : Results.Ok(ToResponse(order, false, null, context));
    }
    catch (DatabaseDeadlineExceededException exception)
    {
        loggerFactory.CreateLogger("Orders").LogWarning(
            exception,
            "Order read exceeded its request deadline for {OperationId}.",
            operationId);
        return Results.Json(
            new { error = "database_deadline_exceeded", operationId, traceId = TraceId(context) },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (DatabaseOperationUnavailableException exception)
    {
        loggerFactory.CreateLogger("Orders").LogError(
            exception,
            "Database retries were exhausted for read {OperationId}; {ExceptionType}: {ExceptionMessage}",
            operationId,
            exception.InnerException?.GetType().FullName,
            exception.InnerException?.Message);
        return Results.Json(
            new { error = "database_unavailable", operationId, traceId = TraceId(context) },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
    catch (NpgsqlException exception)
    {
        loggerFactory.CreateLogger("Orders").LogError(
            exception,
            "Database read failed for order {OperationId}.",
            operationId);
        return Results.Json(
            new { error = "database_unavailable", operationId, traceId = TraceId(context) },
            statusCode: StatusCodes.Status503ServiceUnavailable);
    }
})
.WithName("GetOrder")
.RequireAuthorization();

app.Run();

static OrderResponse ToResponse(
    OrderRecord order,
    bool replayed,
    string? runId,
    HttpContext context) =>
    new(
        order.OperationId,
        order.Payload,
        order.PayloadSha256,
        order.CreatedAtUtc,
        replayed,
        ReplicaId(),
        Revision(),
        runId,
        TraceId(context));

static string ReplicaId() =>
    Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID") ?? "local";

static string Revision() =>
    Environment.GetEnvironmentVariable("LAB_SOURCE_REVISION") ?? "local";

static string TraceId(HttpContext context) =>
    System.Diagnostics.Activity.Current?.TraceId.ToString()
    ?? context.TraceIdentifier;

public partial class Program;
