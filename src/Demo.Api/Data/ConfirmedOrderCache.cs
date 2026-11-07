using Azure.Core;
using System.Text.Json;
using StackExchange.Redis;

namespace Demo.Api.Data;

public interface IConfirmedOrderCache
{
    Task<OrderRecord?> GetAsync(Guid operationId, CancellationToken cancellationToken);
    Task SetAsync(OrderRecord order, CancellationToken cancellationToken);
}

public sealed class RedisOrderCache : IConfirmedOrderCache, IDisposable
{
    private readonly Lazy<Task<ConnectionMultiplexer>> _connection;
    private readonly ILogger<RedisOrderCache> _logger;
    private long _hits, _misses, _writes, _readFailures, _writeFailures;

    public RedisOrderCache(IConfiguration configuration, TokenCredential credential, ILogger<RedisOrderCache> logger)
    {
        _logger = logger;
        var host = configuration["Orders:SharedCacheHost"];
        if (string.IsNullOrWhiteSpace(host) || !host.EndsWith(".redis.azure.net", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Orders:SharedCacheHost must identify the qualified Azure Managed Redis endpoint.");
        _connection = new Lazy<Task<ConnectionMultiplexer>>(async () =>
        {
            var options = ConfigurationOptions.Parse($"{host}:10000");
            options.Ssl = true;
            options.AbortOnConnectFail = false;
            options.ConnectTimeout = 5000;
            options.AsyncTimeout = 1000;
            options.Protocol = RedisProtocol.Resp3;
            await options.ConfigureForAzureWithTokenCredentialAsync(credential);
            return await ConnectionMultiplexer.ConnectAsync(options);
        });
    }

    public object Snapshot => new
    {
        enabled = true,
        connected = _connection.IsValueCreated && _connection.Value.IsCompletedSuccessfully && _connection.Value.Result.IsConnected,
        hits = Interlocked.Read(ref _hits), misses = Interlocked.Read(ref _misses), writes = Interlocked.Read(ref _writes),
        readFailures = Interlocked.Read(ref _readFailures), writeFailures = Interlocked.Read(ref _writeFailures)
    };

    public async Task InitializeAsync(CancellationToken cancellationToken)
    {
        var connection = await _connection.Value.WaitAsync(TimeSpan.FromSeconds(30), cancellationToken);
        if (!connection.IsConnected)
            throw new InvalidOperationException("Private shared confirmed-order cache did not become connected.");
        _logger.LogInformation("Private shared confirmed-order cache initialized with Entra authentication and verified TLS.");
    }

    public async Task<OrderRecord?> GetAsync(Guid operationId, CancellationToken cancellationToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(1));
        try
        {
            var connection = await _connection.Value.WaitAsync(deadline.Token);
            var value = await connection.GetDatabase().StringGetAsync(Key(operationId)).WaitAsync(deadline.Token);
            if (value.IsNull)
            {
                Interlocked.Increment(ref _misses);
                return null;
            }
            var order = JsonSerializer.Deserialize<OrderRecord>((string)value!);
            if (order is null || order.OperationId != operationId)
                throw new InvalidDataException("Shared confirmed-order cache returned an inconsistent record identity.");
            Interlocked.Increment(ref _hits);
            return order;
        }
        catch (RedisException exception)
        {
            Interlocked.Increment(ref _readFailures);
            _logger.LogWarning(exception, "Shared confirmed-order read failed; querying PostgreSQL.");
            return null;
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            Interlocked.Increment(ref _readFailures);
            _logger.LogWarning(exception, "Shared confirmed-order read deadline exceeded; querying PostgreSQL.");
            return null;
        }
    }

    public async Task SetAsync(OrderRecord order, CancellationToken cancellationToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(TimeSpan.FromSeconds(1));
        try
        {
            var connection = await _connection.Value.WaitAsync(deadline.Token);
            var stored = await connection.GetDatabase().StringSetAsync(
                Key(order.OperationId), JsonSerializer.Serialize(order), TimeSpan.FromHours(1)).WaitAsync(deadline.Token);
            if (!stored) throw new InvalidOperationException("Shared confirmed-order cache rejected its write.");
            Interlocked.Increment(ref _writes);
        }
        catch (RedisException exception)
        {
            Interlocked.Increment(ref _writeFailures);
            _logger.LogWarning(exception, "Shared confirmed-order cache update failed after PostgreSQL confirmed the row.");
        }
        catch (OperationCanceledException exception) when (!cancellationToken.IsCancellationRequested)
        {
            Interlocked.Increment(ref _writeFailures);
            _logger.LogWarning(exception, "Shared cache update deadline exceeded after PostgreSQL confirmed the row.");
        }
    }

    private static string Key(Guid operationId) => $"csl:confirmed-orders:{operationId:D}";

    public void Dispose()
    {
        if (_connection.IsValueCreated && _connection.Value.IsCompletedSuccessfully)
            _connection.Value.Result.Dispose();
    }
}
