using System.Text.Json;

namespace Demo.Api.Services;

public enum ReadinessFaultStatus
{
    None,
    Active,
    Invalid
}

public sealed record ReadinessFaultLease(DateTimeOffset ExpiresAtUtc, string Reason);

public sealed record ReadinessFaultState(
    ReadinessFaultStatus Status,
    DateTimeOffset? ExpiresAtUtc,
    string? Reason);

public sealed class ReadinessFaultStore(IConfiguration configuration)
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly string _path = configuration["Chaos:ReadinessFaultPath"]
        ?? "/tmp/csl-readiness-fault.json";

    public ReadinessFaultState GetState()
    {
        if (!File.Exists(_path))
        {
            return new ReadinessFaultState(ReadinessFaultStatus.None, null, null);
        }

        ReadinessFaultLease? lease;
        try
        {
            lease = JsonSerializer.Deserialize<ReadinessFaultLease>(
                File.ReadAllText(_path),
                JsonOptions);
        }
        catch (JsonException)
        {
            return new ReadinessFaultState(ReadinessFaultStatus.Invalid, null, "invalid fault state");
        }

        if (lease is null || string.IsNullOrWhiteSpace(lease.Reason))
        {
            return new ReadinessFaultState(ReadinessFaultStatus.Invalid, null, "invalid fault state");
        }

        if (lease.ExpiresAtUtc <= DateTimeOffset.UtcNow)
        {
            File.Delete(_path);
            return new ReadinessFaultState(ReadinessFaultStatus.None, null, null);
        }

        return new ReadinessFaultState(
            ReadinessFaultStatus.Active,
            lease.ExpiresAtUtc,
            lease.Reason);
    }
}
