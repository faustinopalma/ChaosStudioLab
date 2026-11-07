using Demo.Api.Contracts;
using Microsoft.Extensions.Caching.Memory;

namespace Demo.Api.Data;

public sealed class CachedOrderRepository(IOrderRepository repository) : IOrderRepository, IDisposable
{
    private readonly MemoryCache _cache = new(new MemoryCacheOptions { SizeLimit = 10000 });
    private static readonly TimeSpan Retention = TimeSpan.FromHours(1);
    private long _hits;
    private long _misses;

    public long Hits => Interlocked.Read(ref _hits);
    public long Misses => Interlocked.Read(ref _misses);
    public int Entries => _cache.Count;

    public async Task<OrderWriteResult> CreateOrGetAsync(
        Guid operationId,
        OrderPayload payload,
        string payloadSha256,
        CancellationToken cancellationToken)
    {
        var result = await repository.CreateOrGetAsync(
            operationId, payload, payloadSha256, cancellationToken);
        Remember(result.Order);
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
        var order = await repository.GetAsync(operationId, cancellationToken);
        if (order is not null)
        {
            Remember(order);
        }
        return order;
    }

    public Task PingAsync(CancellationToken cancellationToken) =>
        repository.PingAsync(cancellationToken);

    public void Dispose() => _cache.Dispose();

    private void Remember(OrderRecord order) =>
        _cache.Set(order.OperationId, order,
            new MemoryCacheEntryOptions { Size = 1, AbsoluteExpirationRelativeToNow = Retention });
}
