using Demo.Api.Data;
using Npgsql;

namespace Demo.Api.Services;

public sealed record DatabaseHealthResult(bool Healthy, string Status);

public sealed class DatabaseHealthProbe(
    IOrderRepository repository,
    ILogger<DatabaseHealthProbe> logger)
{
    public async Task<DatabaseHealthResult> CheckAsync(CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(1));

        try
        {
            await repository.PingAsync(timeout.Token);
            return new DatabaseHealthResult(true, "healthy");
        }
        catch (NpgsqlException exception)
        {
            logger.LogWarning(exception, "Database readiness check failed.");
            return new DatabaseHealthResult(false, "unavailable");
        }
        catch (IOException exception)
        {
            logger.LogWarning(exception, "Database readiness check failed.");
            return new DatabaseHealthResult(false, "unavailable");
        }
        catch (TimeoutException exception)
        {
            logger.LogWarning(exception, "Database readiness check timed out.");
            return new DatabaseHealthResult(false, "timeout");
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            return new DatabaseHealthResult(false, "timeout");
        }
    }
}
