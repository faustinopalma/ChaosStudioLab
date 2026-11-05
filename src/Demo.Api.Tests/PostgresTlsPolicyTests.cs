using System.Security.Cryptography.X509Certificates;
using Demo.Api.Data;
using Xunit;

namespace Demo.Api.Tests;

public sealed class PostgresTlsPolicyTests
{
    [Fact]
    public void ChainPolicyKeepsOnlineRevocationWithBoundedRetrieval()
    {
        var policy = PostgresTlsPolicy.CreateChainPolicy();

        Assert.Equal(X509RevocationMode.Online, policy.RevocationMode);
        Assert.Equal(X509ChainTrustMode.System, policy.TrustMode);
        Assert.True(policy.UrlRetrievalTimeout > TimeSpan.Zero);
        Assert.True(policy.UrlRetrievalTimeout < TimeSpan.FromSeconds(3));
    }

    [Fact]
    public void ChainPolicyToleratesOnlyUnknownRevocationStatus()
    {
        var flags = PostgresTlsPolicy.CreateChainPolicy().VerificationFlags;

        Assert.True(flags.HasFlag(X509VerificationFlags.IgnoreEndRevocationUnknown));
        Assert.False(flags.HasFlag(X509VerificationFlags.AllowUnknownCertificateAuthority));
        Assert.False(flags.HasFlag(X509VerificationFlags.IgnoreNotTimeValid));
        Assert.False(flags.HasFlag(X509VerificationFlags.IgnoreInvalidName));
        Assert.False(flags.HasFlag(X509VerificationFlags.IgnoreWrongUsage));
    }
}
