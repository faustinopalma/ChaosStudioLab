using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Demo.Api.Contracts;
using Demo.Api.Data;
using Npgsql;

namespace Demo.Api.Services;

public sealed record OrderValidationResult(
    Guid OperationId,
    OrderPayload Payload,
    string PayloadSha256);

public sealed class OrderService(
    IOrderRepository repository,
    ILogger<OrderService> logger)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private static readonly TimeSpan RequestDeadline = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan[] RetryDelays =
    [
        TimeSpan.FromMilliseconds(100),
        TimeSpan.FromMilliseconds(250)
    ];

    public static bool TryValidate(
        CreateOrderRequest? request,
        out OrderValidationResult? result,
        out string error)
    {
        result = null;
        error = string.Empty;

        if (request?.OperationId is not Guid operationId || operationId == Guid.Empty)
        {
            error = "operationId must be a non-empty GUID.";
            return false;
        }

        if (request.Payload is not { } input)
        {
            error = "payload is required.";
            return false;
        }

        var sku = input.Sku?.Trim();
        if (string.IsNullOrWhiteSpace(sku) || sku.Length > 64)
        {
            error = "payload.sku must contain 1 to 64 characters.";
            return false;
        }

        if (input.Quantity is < 1 or > 10000)
        {
            error = "payload.quantity must be between 1 and 10000.";
            return false;
        }

        var notes = input.Notes?.Trim();
        if (notes?.Length > 1000)
        {
            error = "payload.notes must be at most 1000 characters.";
            return false;
        }

        var payload = new OrderPayload(sku, input.Quantity, notes);
        var payloadJson = JsonSerializer.Serialize(payload, JsonOptions);
        var checksum = Convert.ToHexStringLower(
            SHA256.HashData(Encoding.UTF8.GetBytes(payloadJson)));

        result = new OrderValidationResult(operationId, payload, checksum);
        return true;
    }

    public Task<OrderWriteResult> CreateAsync(
        OrderValidationResult order,
        CancellationToken cancellationToken) =>
        ExecuteWithRetryAsync(
            token => repository.CreateOrGetAsync(
                order.OperationId,
                order.Payload,
                order.PayloadSha256,
                token),
            order.OperationId,
            cancellationToken);

    public Task<OrderRecord?> GetAsync(
        Guid operationId,
        CancellationToken cancellationToken) =>
        ExecuteWithRetryAsync(
            token => repository.GetAsync(operationId, token),
            operationId,
            cancellationToken);

    private async Task<T> ExecuteWithRetryAsync<T>(
        Func<CancellationToken, Task<T>> operation,
        Guid operationId,
        CancellationToken cancellationToken)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        deadline.CancelAfter(RequestDeadline);

        for (var attempt = 0; ; attempt++)
        {
            try
            {
                return await operation(deadline.Token);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                throw new DatabaseDeadlineExceededException();
            }
            catch (Exception exception) when (IsTransient(exception) && attempt < RetryDelays.Length)
            {
                logger.LogWarning(
                    exception,
                    "Transient database failure for operation {OperationId}; retry {RetryNumber}; {ExceptionType}: {ExceptionMessage}",
                    operationId,
                    attempt + 1,
                    exception.GetType().FullName,
                    exception.Message);

                var jitter = TimeSpan.FromMilliseconds(Random.Shared.Next(0, 100));
                try
                {
                    await Task.Delay(RetryDelays[attempt] + jitter, deadline.Token);
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    throw new DatabaseDeadlineExceededException();
                }
            }
            catch (Exception exception) when (IsTransient(exception))
            {
                throw new DatabaseOperationUnavailableException(exception);
            }
        }
    }

    private static bool IsTransient(Exception exception) =>
        exception is TimeoutException
        or IOException
        or NpgsqlException { IsTransient: true };
}
