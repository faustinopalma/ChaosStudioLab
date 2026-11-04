using System.Collections.Concurrent;
using Demo.Api.Contracts;
using Demo.Api.Data;
using Demo.Api.Services;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Demo.Api.Tests;

public sealed class OrderServiceTests
{
    [Fact]
    public async Task Repeated_operation_with_same_payload_returns_existing_order()
    {
        var repository = new InMemoryOrderRepository();
        var service = new OrderService(repository, NullLogger<OrderService>.Instance);
        var operationId = Guid.NewGuid();
        var request = new CreateOrderRequest(
            operationId,
            new OrderPayload("sku-1", 2, "sample"));

        Assert.True(OrderService.TryValidate(request, out var validated, out _));

        var first = await service.CreateAsync(validated!, CancellationToken.None);
        var second = await service.CreateAsync(validated!, CancellationToken.None);

        Assert.False(first.Replayed);
        Assert.True(second.Replayed);
        Assert.Equal(first.Order, second.Order);
    }

    [Fact]
    public async Task Repeated_operation_with_different_payload_returns_conflict()
    {
        var repository = new InMemoryOrderRepository();
        var service = new OrderService(repository, NullLogger<OrderService>.Instance);
        var operationId = Guid.NewGuid();
        var firstRequest = new CreateOrderRequest(
            operationId,
            new OrderPayload("sku-1", 2, null));
        var conflictingRequest = new CreateOrderRequest(
            operationId,
            new OrderPayload("sku-2", 2, null));

        Assert.True(OrderService.TryValidate(firstRequest, out var first, out _));
        Assert.True(OrderService.TryValidate(conflictingRequest, out var conflicting, out _));
        await service.CreateAsync(first!, CancellationToken.None);

        var exception = await Assert.ThrowsAsync<OrderConflictException>(
            () => service.CreateAsync(conflicting!, CancellationToken.None));

        Assert.Equal(operationId, exception.OperationId);
    }

    [Fact]
    public async Task Transient_database_errors_are_retried_twice()
    {
        var repository = new TransientOrderRepository(failures: 2);
        var service = new OrderService(repository, NullLogger<OrderService>.Instance);
        Assert.True(
            OrderService.TryValidate(
                new CreateOrderRequest(
                    Guid.NewGuid(),
                    new OrderPayload("sku-1", 1, null)),
                out var validated,
                out _));

        var result = await service.CreateAsync(validated!, CancellationToken.None);

        Assert.False(result.Replayed);
        Assert.Equal(3, repository.CreateCalls);
    }

    [Fact]
    public async Task Transient_database_errors_fail_explicitly_after_two_retries()
    {
        var repository = new TransientOrderRepository(failures: 3);
        var service = new OrderService(repository, NullLogger<OrderService>.Instance);
        Assert.True(
            OrderService.TryValidate(
                new CreateOrderRequest(
                    Guid.NewGuid(),
                    new OrderPayload("sku-1", 1, null)),
                out var validated,
                out _));

        await Assert.ThrowsAsync<DatabaseOperationUnavailableException>(
            () => service.CreateAsync(validated!, CancellationToken.None));

        Assert.Equal(3, repository.CreateCalls);
    }

    [Theory]
    [InlineData("", "payload.sku must contain 1 to 64 characters.")]
    [InlineData(" ", "payload.sku must contain 1 to 64 characters.")]
    public void Invalid_payload_is_rejected(string? sku, string expectedError)
    {
        var request = new CreateOrderRequest(
            Guid.NewGuid(),
            new OrderPayload(sku, 1, null));

        Assert.False(OrderService.TryValidate(request, out var result, out var error));
        Assert.Null(result);
        Assert.Equal(expectedError, error);
    }

    [Fact]
    public void Missing_payload_is_rejected()
    {
        var request = new CreateOrderRequest(Guid.NewGuid(), null);

        Assert.False(OrderService.TryValidate(request, out var result, out var error));
        Assert.Null(result);
        Assert.Equal("payload is required.", error);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(10001)]
    public void Quantity_outside_the_contract_is_rejected(int quantity)
    {
        var request = new CreateOrderRequest(
            Guid.NewGuid(),
            new OrderPayload("sku-1", quantity, null));

        Assert.False(OrderService.TryValidate(request, out _, out var error));
        Assert.Equal("payload.quantity must be between 1 and 10000.", error);
    }

    private sealed class InMemoryOrderRepository : IOrderRepository
    {
        private readonly ConcurrentDictionary<Guid, OrderRecord> _orders = new();

        public Task<OrderWriteResult> CreateOrGetAsync(
            Guid operationId,
            OrderPayload payload,
            string payloadSha256,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var candidate = new OrderRecord(
                operationId,
                payload,
                payloadSha256,
                DateTimeOffset.UtcNow);
            var existing = _orders.GetOrAdd(operationId, candidate);
            if (!string.Equals(
                    existing.PayloadSha256,
                    payloadSha256,
                    StringComparison.Ordinal))
            {
                throw new OrderConflictException(operationId);
            }

            return Task.FromResult(new OrderWriteResult(
                existing,
                !ReferenceEquals(existing, candidate)));
        }

        public Task<OrderRecord?> GetAsync(
            Guid operationId,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            _orders.TryGetValue(operationId, out var order);
            return Task.FromResult(order);
        }

        public Task PingAsync(CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            return Task.CompletedTask;
        }
    }

    private sealed class TransientOrderRepository(int failures) : IOrderRepository
    {
        private int _failuresRemaining = failures;
        public int CreateCalls { get; private set; }

        public Task<OrderWriteResult> CreateOrGetAsync(
            Guid operationId,
            OrderPayload payload,
            string payloadSha256,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            CreateCalls++;
            if (Interlocked.Decrement(ref _failuresRemaining) >= 0)
            {
                throw new TimeoutException("Transient test timeout.");
            }

            var order = new OrderRecord(
                operationId,
                payload,
                payloadSha256,
                DateTimeOffset.UtcNow);
            return Task.FromResult(new OrderWriteResult(order, Replayed: false));
        }

        public Task<OrderRecord?> GetAsync(
            Guid operationId,
            CancellationToken cancellationToken) =>
            throw new NotSupportedException();

        public Task PingAsync(CancellationToken cancellationToken) =>
            throw new NotSupportedException();
    }
}
