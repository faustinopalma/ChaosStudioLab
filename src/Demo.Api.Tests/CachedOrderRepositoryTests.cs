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

    [Fact]
    public async Task New_confirmed_rows_are_admitted_at_the_exact_capacity_limit()
    {
        var inner = new Repository();
        using var cache = new CachedOrderRepository(inner);
        for (var index = 0; index <= 10000; index++)
        {
            var id = Guid.NewGuid();
            var committed = await cache.CreateOrGetAsync(id, inner.Order.Payload, inner.Order.PayloadSha256, CancellationToken.None);
            Assert.InRange(cache.Entries, 1, 10000);
            inner.Unavailable = true;
            Assert.Equal(committed.Order, await cache.GetAsync(id, CancellationToken.None));
            inner.Unavailable = false;
        }
        Assert.True(cache.Compactions > 0);
    }

    [Fact]
    public async Task Frequent_confirmed_reads_survive_single_use_write_pressure()
    {
        var inner = new Repository();
        using var cache = new CachedOrderRepository(inner);
        await cache.GetAsync(inner.Order.OperationId, CancellationToken.None);
        for (var index = 0; index < 20000; index++)
        {
            await cache.CreateOrGetAsync(Guid.NewGuid(), inner.Order.Payload, inner.Order.PayloadSha256, CancellationToken.None);
            inner.Unavailable = true;
            Assert.Equal(inner.Order, await cache.GetAsync(inner.Order.OperationId, CancellationToken.None));
            inner.Unavailable = false;
        }
        Assert.InRange(cache.Entries, 1, 10000);
        Assert.True(cache.Compactions > 0);
    }

    [Fact]
    public async Task A_cold_worker_reads_another_workers_confirmed_write_during_database_outage()
    {
        var writer = new Repository();
        var reader = new Repository { Unavailable = true };
        var shared = new SharedCache();
        using var first = new CachedOrderRepository(writer, shared);
        using var second = new CachedOrderRepository(reader, shared);
        var committed = await first.CreateOrGetAsync(writer.Order.OperationId, writer.Order.Payload, writer.Order.PayloadSha256, CancellationToken.None);
        Assert.Equal(committed.Order, await second.GetAsync(committed.Order.OperationId, CancellationToken.None));
        Assert.Equal(0, reader.Reads);
        await Assert.ThrowsAsync<TimeoutException>(() => second.CreateOrGetAsync(
            committed.Order.OperationId, committed.Order.Payload, committed.Order.PayloadSha256, CancellationToken.None));
        await Assert.ThrowsAsync<TimeoutException>(() => second.PingAsync(CancellationToken.None));
    }

    [Fact]
    public async Task Missing_shared_rows_still_query_postgresql_and_do_not_fabricate_orders()
    {
        var inner = new Repository { Missing = true };
        using var cache = new CachedOrderRepository(inner, new SharedCache());
        Assert.Null(await cache.GetAsync(inner.Order.OperationId, CancellationToken.None));
        Assert.Equal(1, inner.Reads);
        Assert.Equal(0, cache.Entries);
    }

    private sealed class SharedCache : IConfirmedOrderCache
    {
        private readonly Dictionary<Guid, OrderRecord> _rows = [];
        public Task<OrderRecord?> GetAsync(Guid operationId, CancellationToken cancellationToken) =>
            Task.FromResult(_rows.GetValueOrDefault(operationId));
        public Task SetAsync(OrderRecord order, CancellationToken cancellationToken)
        {
            _rows[order.OperationId] = order;
            return Task.CompletedTask;
        }
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
            return Task.FromResult(new OrderWriteResult(Order with
            {
                OperationId = operationId, Payload = payload, PayloadSha256 = payloadSha256
            }, Replayed: false));
        }

        public Task PingAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (Unavailable) { throw new TimeoutException("Explicit test outage."); }
            return Task.CompletedTask;
        }
    }
}
