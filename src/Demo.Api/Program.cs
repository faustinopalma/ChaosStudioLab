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
        // Npgsql 10 defaults to GSS Encryption Mode=Prefer, which probes Kerberos/SSPI credentials
        // before every physical open. On Windows App Service that probe stalls for seconds and
        // exceeds the connect timeout; the lab authenticates with Entra tokens over verified TLS.
        GssEncryptionMode = GssEncryptionMode.Disable,
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
builder.Services.AddSingleton<NpgsqlOrderRepository>();
if (!string.IsNullOrWhiteSpace(builder.Configuration["Orders:SharedCacheHost"]))
{
    if (!builder.Configuration.GetValue<bool>("Orders:CacheImmutableReads"))
        throw new InvalidOperationException("Shared confirmed-order caching requires Orders:CacheImmutableReads.");
    builder.Services.AddSingleton<RedisOrderCache>();
    builder.Services.AddSingleton<IConfirmedOrderCache>(services => services.GetRequiredService<RedisOrderCache>());
}
builder.Services.AddSingleton<IOrderRepository>(services =>
{
    var repository = services.GetRequiredService<NpgsqlOrderRepository>();
    return builder.Configuration.GetValue<bool>("Orders:CacheImmutableReads")
        ? new CachedOrderRepository(repository, services.GetService<IConfirmedOrderCache>())
        : repository;
});
builder.Services.AddSingleton<OrderService>();
builder.Services.AddSingleton<DatabaseHealthProbe>();
builder.Services.AddSingleton<DatabaseOpenDiagnostics>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<ReplicaFault>();
builder.Services.AddHostedService<DatabaseWarmupService>();

var app = builder.Build();
if (app.Services.GetService<RedisOrderCache>() is { } sharedCache)
    await sharedCache.InitializeAsync(app.Lifetime.ApplicationStopping);
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

// Platform readiness probe for Container Apps: process health plus the lab replica-fault lease.
// It deliberately ignores PostgreSQL so a database failover keeps every replica in rotation.
app.MapGet("/health/serving", (ReplicaFault fault) =>
{
    var state = fault.Current;
    return state.Active
        ? Results.Json(new { status = "withdrawn", replicaId = ReplicaId(), state.ExpiresAtUtc, state.Reason },
            statusCode: StatusCodes.Status503ServiceUnavailable)
        : Results.Ok(new { status = "serving", replicaId = ReplicaId() });
});

app.MapPost("/diagnostics/replica-fault", (ReplicaFaultRequest? request, ReplicaFault fault, HttpContext context) =>
{
    if (request is null || request.Mode is not ("unready" or "exit"))
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["mode"] = ["Use unready or exit."] });
    var identity = new { replicaId = ReplicaId(), processId = Environment.ProcessId, processStartedAtUtc, acceptedAtUtc = DateTimeOffset.UtcNow };
    if (request.Mode == "exit")
    {
        // Abrupt replica crash: the response is flushed first, then the process is killed without graceful shutdown.
        context.Response.OnCompleted(() =>
        {
            System.Diagnostics.Process.GetCurrentProcess().Kill();
            return Task.CompletedTask;
        });
        return Results.Json(new { identity.replicaId, identity.processId, identity.processStartedAtUtc, identity.acceptedAtUtc, mode = "exit" },
            statusCode: StatusCodes.Status202Accepted);
    }
    try
    {
        var activated = fault.TryActivate(request.TtlSeconds, request.Reason ?? string.Empty, out var state);
        return Results.Json(new { identity.replicaId, identity.processId, identity.processStartedAtUtc, identity.acceptedAtUtc,
                mode = "unready", state.ExpiresAtUtc, alreadyActive = !activated },
            statusCode: activated ? StatusCodes.Status202Accepted : StatusCodes.Status409Conflict);
    }
    catch (ArgumentException exception)
    {
        return Results.ValidationProblem(new Dictionary<string, string[]> { ["request"] = [exception.Message] });
    }
}).RequireAuthorization();

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

app.MapGet("/diagnostics/read-cache", (IOrderRepository repository, IServiceProvider services) =>
    repository is CachedOrderRepository cache
        ? Results.Ok(new { enabled = true, hits = cache.Hits, misses = cache.Misses, entries = cache.Entries, compactions = cache.Compactions,
            shared = services.GetService<RedisOrderCache>()?.Snapshot })
        : Results.Ok(new { enabled = false, hits = 0L, misses = 0L, entries = 0, compactions = 0L }))
    .RequireAuthorization();

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
    Environment.GetEnvironmentVariable("WEBSITE_INSTANCE_ID")
    ?? Environment.GetEnvironmentVariable("CONTAINER_APP_REPLICA_NAME")
    ?? "local";

static string Revision() =>
    Environment.GetEnvironmentVariable("LAB_SOURCE_REVISION") ?? "local";

static string TraceId(HttpContext context) =>
    System.Diagnostics.Activity.Current?.TraceId.ToString()
    ?? context.TraceIdentifier;

public partial class Program;

public sealed record ReplicaFaultRequest(string? Mode, int TtlSeconds, string? Reason);
