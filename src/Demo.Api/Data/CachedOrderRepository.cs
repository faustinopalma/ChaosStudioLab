using Demo.Api.Contracts;
using Microsoft.Extensions.Caching.Memory;

namespace Demo.Api.Data;

public sealed class CachedOrderRepository(IOrderRepository repository, IConfirmedOrderCache? sharedCache = null) : IOrderRepository, IDisposable
{
    private const int Capacity = 10000;
    private readonly MemoryCache _cache = new(new MemoryCacheOptions { SizeLimit = Capacity });
    private readonly object _admission = new();
    private static readonly TimeSpan Retention = TimeSpan.FromHours(1);
    private long _hits;
    private long _misses;
    private long _compactions;

    public long Hits => Interlocked.Read(ref _hits);
    public long Misses => Interlocked.Read(ref _misses);
    public int Entries => _cache.Count;
    public long Compactions => Interlocked.Read(ref _compactions);

    public async Task<OrderWriteResult> CreateOrGetAsync(
        Guid operationId,
        OrderPayload payload,
        string payloadSha256,
        CancellationToken cancellationToken)
    {
        var result = await repository.CreateOrGetAsync(
            operationId, payload, payloadSha256, cancellationToken);
        Remember(result.Order);
        if (sharedCache is not null)
            await sharedCache.SetAsync(result.Order, cancellationToken);
        return result;
    }

    public async Task<OrderRecord?> GetAsync(Guid operationId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        if (_cache.TryGetValue(operationId, out OrderRecord? cached) && cached is not null)
        {
            Interlocked.Increment(ref _hits);
            return cached;
        }

        Interlocked.Increment(ref _misses);
        if (sharedCache is not null)
        {
            var confirmed = await sharedCache.GetAsync(operationId, cancellationToken);
            if (confirmed is not null)
            {
                Remember(confirmed);
                return confirmed;
            }
        }
        var order = await repository.GetAsync(operationId, cancellationToken);
        if (order is not null)
        {
            Remember(order);
            if (sharedCache is not null)
                await sharedCache.SetAsync(order, cancellationToken);
        }
        return order;
    }

    public Task PingAsync(CancellationToken cancellationToken) =>
        repository.PingAsync(cancellationToken);

    public void Dispose() => _cache.Dispose();

    private void Remember(OrderRecord order)
    {
        lock (_admission)
        {
            if (_cache.Count >= Capacity && !_cache.TryGetValue(order.OperationId, out _))
            {
                _cache.Compact(0.1);
                Interlocked.Increment(ref _compactions);
            }
            _cache.Set(order.OperationId, order,
                new MemoryCacheEntryOptions { Size = 1, AbsoluteExpirationRelativeToNow = Retention });
        }
    }
}
