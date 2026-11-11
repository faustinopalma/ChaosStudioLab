using Demo.Api.Services;
using Xunit;

namespace Demo.Api.Tests;

public sealed class ReplicaFaultTests
{
    private sealed class ManualClock(DateTimeOffset now) : TimeProvider
    {
        public DateTimeOffset Now { get; set; } = now;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    [Fact]
    public void Lease_withdraws_readiness_until_its_ttl_expires()
    {
        var clock = new ManualClock(DateTimeOffset.Parse("2026-11-11T10:00:00Z"));
        var fault = new ReplicaFault(clock);

        Assert.True(fault.TryActivate(360, "HA-REPLICA-001", out var state));
        Assert.True(fault.Current.Active);
        Assert.Equal(clock.Now.AddSeconds(360), state.ExpiresAtUtc);

        clock.Now = clock.Now.AddSeconds(359);
        Assert.True(fault.Current.Active);
        clock.Now = clock.Now.AddSeconds(1);
        Assert.False(fault.Current.Active);
    }

    [Fact]
    public void Active_lease_is_not_extended_by_a_second_request()
    {
        var clock = new ManualClock(DateTimeOffset.Parse("2026-11-11T10:00:00Z"));
        var fault = new ReplicaFault(clock);
        Assert.True(fault.TryActivate(60, "first", out var first));

        clock.Now = clock.Now.AddSeconds(30);
        Assert.False(fault.TryActivate(600, "second", out var second));
        Assert.Equal(first.ExpiresAtUtc, second.ExpiresAtUtc);
        Assert.Equal("first", second.Reason);
    }

    [Theory]
    [InlineData(0, "valid")]
    [InlineData(601, "valid")]
    [InlineData(60, "")]
    [InlineData(60, "has space")]
    public void Invalid_requests_are_rejected(int ttlSeconds, string reason)
    {
        var fault = new ReplicaFault(TimeProvider.System);
        Assert.ThrowsAny<ArgumentException>(() => fault.TryActivate(ttlSeconds, reason, out _));
        Assert.False(fault.Current.Active);
    }
}
