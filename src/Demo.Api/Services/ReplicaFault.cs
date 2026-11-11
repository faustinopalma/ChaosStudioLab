namespace Demo.Api.Services;

public sealed record ReplicaFaultState(bool Active, DateTimeOffset? ExpiresAtUtc, string? Reason);

/// <summary>
/// Lab-only, in-memory readiness withdrawal for one replica. It is independent of PostgreSQL so a
/// database outage cannot block fault control, and it expires on its own after the requested TTL.
/// </summary>
public sealed class ReplicaFault(TimeProvider clock)
{
    public const int MaximumTtlSeconds = 600;
    private readonly object _gate = new();
    private DateTimeOffset? _expiresAtUtc;
    private string? _reason;

    public ReplicaFaultState Current
    {
        get
        {
            lock (_gate)
            {
                if (_expiresAtUtc is { } expiry && expiry <= clock.GetUtcNow())
                {
                    _expiresAtUtc = null;
                    _reason = null;
                }
                return new ReplicaFaultState(_expiresAtUtc is not null, _expiresAtUtc, _reason);
            }
        }
    }

    public bool TryActivate(int ttlSeconds, string reason, out ReplicaFaultState state)
    {
        if (ttlSeconds is < 1 or > MaximumTtlSeconds)
            throw new ArgumentOutOfRangeException(nameof(ttlSeconds));
        if (string.IsNullOrWhiteSpace(reason) || reason.Length > 80 ||
            !reason.All(c => char.IsAsciiLetterOrDigit(c) || c is '.' or '_' or '-'))
            throw new ArgumentException("Reason must use 1-80 letters, digits, dot, underscore or hyphen.", nameof(reason));
        lock (_gate)
        {
            var current = Current;
            if (current.Active)
            {
                state = current;
                return false;
            }
            _expiresAtUtc = clock.GetUtcNow().AddSeconds(ttlSeconds);
            _reason = reason;
            state = new ReplicaFaultState(true, _expiresAtUtc, _reason);
            return true;
        }
    }
}
