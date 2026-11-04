using System.Data;
using System.Text.Json;
using Demo.Api.Contracts;
using Npgsql;
using NpgsqlTypes;

namespace Demo.Api.Data;

public sealed record OrderRecord(
    Guid OperationId,
    OrderPayload Payload,
    string PayloadSha256,
    DateTimeOffset CreatedAtUtc);

public sealed record OrderWriteResult(OrderRecord Order, bool Replayed);

public interface IOrderRepository
{
    Task<OrderWriteResult> CreateOrGetAsync(
        Guid operationId,
        OrderPayload payload,
        string payloadSha256,
        CancellationToken cancellationToken);

    Task<OrderRecord?> GetAsync(Guid operationId, CancellationToken cancellationToken);

    Task PingAsync(CancellationToken cancellationToken);
}

public sealed class NpgsqlOrderRepository(NpgsqlDataSource dataSource) : IOrderRepository
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task<OrderWriteResult> CreateOrGetAsync(
        Guid operationId,
        OrderPayload payload,
        string payloadSha256,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var transaction = await connection.BeginTransactionAsync(
            IsolationLevel.ReadCommitted,
            cancellationToken);

        await using var insert = new NpgsqlCommand(
            """
            INSERT INTO orders (operation_id, payload_json, payload_sha256)
            VALUES (@operation_id, @payload_json, @payload_sha256)
            ON CONFLICT (operation_id) DO NOTHING
            """,
            connection,
            transaction);
        insert.Parameters.AddWithValue("operation_id", operationId);
        insert.Parameters.Add(new NpgsqlParameter("payload_json", NpgsqlDbType.Jsonb)
        {
            Value = JsonSerializer.Serialize(payload, JsonOptions)
        });
        insert.Parameters.AddWithValue("payload_sha256", payloadSha256);

        var inserted = await insert.ExecuteNonQueryAsync(cancellationToken);
        var order = await ReadOrderAsync(connection, transaction, operationId, cancellationToken);
        if (order is null)
        {
            throw new InvalidOperationException(
                "The order insert completed without a matching durable row.");
        }

        if (!string.Equals(order.PayloadSha256, payloadSha256, StringComparison.Ordinal))
        {
            throw new OrderConflictException(operationId);
        }

        await transaction.CommitAsync(cancellationToken);
        return new OrderWriteResult(order, inserted == 0);
    }

    public async Task<OrderRecord?> GetAsync(
        Guid operationId,
        CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        return await ReadOrderAsync(connection, transaction: null, operationId, cancellationToken);
    }

    public async Task PingAsync(CancellationToken cancellationToken)
    {
        await using var connection = await dataSource.OpenConnectionAsync(cancellationToken);
        await using var command = new NpgsqlCommand("SELECT 1", connection);
        await command.ExecuteScalarAsync(cancellationToken);
    }

    private static async Task<OrderRecord?> ReadOrderAsync(
        NpgsqlConnection connection,
        NpgsqlTransaction? transaction,
        Guid operationId,
        CancellationToken cancellationToken)
    {
        await using var command = new NpgsqlCommand(
            """
            SELECT operation_id, payload_json::text, payload_sha256, created_at_utc
            FROM orders
            WHERE operation_id = @operation_id
            """,
            connection,
            transaction);
        command.Parameters.AddWithValue("operation_id", operationId);

        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        if (!await reader.ReadAsync(cancellationToken))
        {
            return null;
        }

        var payload = JsonSerializer.Deserialize<OrderPayload>(
            reader.GetString(1),
            JsonOptions);
        if (payload is null)
        {
            throw new InvalidOperationException("The persisted order payload is invalid.");
        }

        return new OrderRecord(
            reader.GetGuid(0),
            payload,
            reader.GetString(2),
            reader.GetFieldValue<DateTimeOffset>(3));
    }
}

public sealed class OrderConflictException(Guid operationId)
    : Exception($"Operation ID '{operationId}' is already committed with a different payload.")
{
    public Guid OperationId { get; } = operationId;
}

public sealed class DatabaseDeadlineExceededException()
    : Exception("The database operation exceeded its five-second request deadline.");

public sealed class DatabaseOperationUnavailableException(Exception innerException)
    : Exception("The database operation failed after its bounded retries.", innerException);
