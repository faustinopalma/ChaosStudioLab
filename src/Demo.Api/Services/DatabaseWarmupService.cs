using System.Diagnostics;
using Npgsql;

namespace Demo.Api.Services;

// Runs before the server starts listening. A fresh worker process otherwise pays JIT, TLS,
// certificate-revocation and managed-identity token costs on its first physical PostgreSQL
// opens, which exceed the 3-second connect timeout and fail user requests in bursts.
public sealed class DatabaseWarmupService(
    IServiceProvider services,
    IConfiguration configuration,
    ILogger<DatabaseWarmupService> logger) : IHostedService
{
    public const int PrefilledConnections = 4;
    private static readonly TimeSpan WarmupBudget = TimeSpan.FromSeconds(45);

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(configuration.GetConnectionString("Postgres")) ||
            string.Equals(configuration["Postgres:Warmup"], "Disabled", StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        using var budget = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        budget.CancelAfter(WarmupBudget);
        var watch = Stopwatch.StartNew();
        try
        {
            var stages = await services.GetRequiredService<DatabaseOpenDiagnostics>().RunAsync(budget.Token);
            logger.LogWarning(
                "Database warmup cold-open stages after {ElapsedMs} ms: {Stages}",
                watch.ElapsedMilliseconds,
                System.Text.Json.JsonSerializer.Serialize(stages));

            var prefilled = await PrefillAsync(services.GetRequiredService<NpgsqlDataSource>(), budget.Token);
            logger.LogWarning(
                "Database warmup completed in {ElapsedMs} ms with {Prefilled} pooled connections; {Runtime}",
                watch.ElapsedMilliseconds,
                prefilled,
                RuntimeSnapshot.Describe());
        }
        catch (Exception exception) when (!cancellationToken.IsCancellationRequested)
        {
            logger.LogWarning(
                "Database warmup stopped after {ElapsedMs} ms; {ExceptionType}: {ExceptionMessage}",
                watch.ElapsedMilliseconds,
                exception.GetType().FullName,
                exception.Message);
        }
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    private async Task<int> PrefillAsync(NpgsqlDataSource dataSource, CancellationToken cancellationToken)
    {
        var connections = new List<NpgsqlConnection>();
        try
        {
            while (connections.Count < PrefilledConnections)
            {
                try
                {
                    var connection = await dataSource.OpenConnectionAsync(cancellationToken);
                    connections.Add(connection);
                    await using var command = new NpgsqlCommand("SELECT 1", connection);
                    await command.ExecuteScalarAsync(cancellationToken);
                }
                catch (NpgsqlException exception) when (!cancellationToken.IsCancellationRequested)
                {
                    logger.LogWarning(
                        "Database warmup open failed; retrying. {ExceptionType}: {ExceptionMessage}",
                        exception.GetType().FullName,
                        exception.Message);
                    await Task.Delay(TimeSpan.FromMilliseconds(250), cancellationToken);
                }
            }

            return connections.Count;
        }
        finally
        {
            foreach (var connection in connections)
            {
                await connection.DisposeAsync();
            }
        }
    }
}
