using Demo.Api.Contracts;
using Demo.Api.Data;
using Xunit;

namespace Demo.Api.Tests;

public sealed class CachedOrderRepositoryTests
{
    [Fact]
    public async Task Confirmed_immutable_read_survives_database_unavailability()
    {
        var inner = new Repository();
        using var cache = new CachedOrderRepository(inner);
        var first = await cache.GetAsync(inner.Order.OperationId, CancellationToken.None);
        inner.Unavailable = true;
        var second = await cache.GetAsync(inner.Order.OperationId, CancellationToken.None);
        Assert.Equal(first, second);
        Assert.Equal(1, inner.Reads);
        Assert.Equal(1, cache.Hits);
        Assert.Equal(1, cache.Misses);
    }

    [Fact]
    public async Task Missing_rows_are_never_cached()
    {
        var inner = new Repository { Missing = true };
        using var cache = new CachedOrderRepository(inner);
        Assert.Null(await cache.GetAsync(inner.Order.OperationId, CancellationToken.None));
        inner.Missing = false;
        Assert.Equal(inner.Order, await cache.GetAsync(inner.Order.OperationId, CancellationToken.None));
        Assert.Equal(2, inner.Reads);
    }

    [Fact]
    public async Task Writes_always_require_database_commit_even_when_order_is_cached()
    {
        var inner = new Repository();
        using var cache = new CachedOrderRepository(inner);
        await cache.CreateOrGetAsync(inner.Order.OperationId, inner.Order.Payload, inner.Order.PayloadSha256, CancellationToken.None);
        inner.Unavailable = true;
        await Assert.ThrowsAsync<TimeoutException>(() =>
            cache.CreateOrGetAsync(inner.Order.OperationId, inner.Order.Payload, inner.Order.PayloadSha256, CancellationToken.None));
        Assert.Equal(inner.Order, await cache.GetAsync(inner.Order.OperationId, CancellationToken.None));
        await Assert.ThrowsAsync<TimeoutException>(() => cache.PingAsync(CancellationToken.None));
    }

    [Fact]
    public async Task Cancellation_is_honored_on_cached_reads()
    {
        var inner = new Repository();
        using var cache = new CachedOrderRepository(inner);
        await cache.GetAsync(inner.Order.OperationId, CancellationToken.None);
        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            cache.GetAsync(inner.Order.OperationId, new CancellationToken(canceled: true)));
    }

    private sealed class Repository : IOrderRepository
    {
        public OrderRecord Order { get; } = new(Guid.NewGuid(), new OrderPayload("sku", 1, null), "checksum", DateTimeOffset.UtcNow);
        public int Reads { get; private set; }
        public bool Unavailable { get; set; }
        public bool Missing { get; set; }

        public Task<OrderRecord?> GetAsync(Guid operationId, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            Reads++;
            if (Unavailable) { throw new TimeoutException("Explicit test outage."); }
            return Task.FromResult(Missing ? null : Order);
        }

        public Task<OrderWriteResult> CreateOrGetAsync(Guid operationId, OrderPayload payload, string payloadSha256, CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Unavailable) { throw new TimeoutException("Explicit test outage."); }
            return Task.FromResult(new OrderWriteResult(Order, Replayed: false));
        }

        public Task PingAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Unavailable) { throw new TimeoutException("Explicit test outage."); }
            return Task.CompletedTask;
        }
    }
}
