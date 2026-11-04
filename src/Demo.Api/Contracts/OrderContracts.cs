namespace Demo.Api.Contracts;

public sealed record OrderPayload(string? Sku, int Quantity, string? Notes);

public sealed record CreateOrderRequest(Guid? OperationId, OrderPayload? Payload);

public sealed record OrderResponse(
    Guid OperationId,
    OrderPayload Payload,
    string PayloadSha256,
    DateTimeOffset CreatedAtUtc,
    bool Replayed,
    string ReplicaId,
    string Revision,
    string? RunId,
    string TraceId);

public sealed record ReadinessResponse(
    string Status,
    string? Reason,
    string ReplicaId,
    string Revision,
    string TraceId);
