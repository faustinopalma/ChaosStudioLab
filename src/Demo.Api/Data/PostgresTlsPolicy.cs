using System.Security.Cryptography.X509Certificates;

namespace Demo.Api.Data;

// Bounds PostgreSQL server-certificate revocation retrieval so a slow OCSP/CRL endpoint cannot
// block a connection open beyond the request deadline. Chain trust and host-name checks stay
// mandatory (SslMode.VerifyFull); only an unreachable revocation source is tolerated (soft-fail).
public static class PostgresTlsPolicy
{
    public static readonly TimeSpan RevocationRetrievalTimeout = TimeSpan.FromSeconds(2);

    public static X509ChainPolicy CreateChainPolicy() => new()
    {
        RevocationMode = X509RevocationMode.Online,
        RevocationFlag = X509RevocationFlag.ExcludeRoot,
        UrlRetrievalTimeout = RevocationRetrievalTimeout,
        VerificationFlags =
            X509VerificationFlags.IgnoreEndRevocationUnknown
            | X509VerificationFlags.IgnoreCertificateAuthorityRevocationUnknown
            | X509VerificationFlags.IgnoreCtlSignerRevocationUnknown
            | X509VerificationFlags.IgnoreRootRevocationUnknown
    };
}
