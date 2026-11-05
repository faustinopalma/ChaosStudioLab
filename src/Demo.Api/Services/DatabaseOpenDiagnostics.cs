using System.Diagnostics;
using System.Net;
using System.Net.Security;
using System.Net.Sockets;
using Azure.Core;
using Demo.Api.Data;
using Npgsql;

namespace Demo.Api.Services;

public static class RuntimeSnapshot
{
    public static string Describe()
    {
        ThreadPool.GetAvailableThreads(out var workers, out var io);
        ThreadPool.GetMinThreads(out var minWorkers, out var minIo);
        return $"threads={ThreadPool.ThreadCount} pending={ThreadPool.PendingWorkItemCount} " +
               $"availableWorkers={workers} availableIo={io} minWorkers={minWorkers} minIo={minIo}";
    }
}

// Measures each stage of a physical PostgreSQL open inside the application process so that
// connection stalls can be attributed to DNS, TCP, TLS, token acquisition or Npgsql itself.
public sealed class DatabaseOpenDiagnostics(
    IConfiguration configuration,
    TokenCredential credential,
    NpgsqlDataSource pooledDataSource)
{
    private static readonly TimeSpan StageTimeout = TimeSpan.FromSeconds(30);

    public async Task<IReadOnlyList<object>> RunAsync(CancellationToken cancellationToken)
    {
        var stages = new List<object> { new { stage = "runtime-before", detail = RuntimeSnapshot.Describe() } };
        var builder = new NpgsqlConnectionStringBuilder(configuration.GetConnectionString("Postgres"));
        var host = builder.Host ?? throw new InvalidOperationException("PostgreSQL host is missing.");
        IPAddress[] addresses = [];

        await MeasureAsync(stages, "dns", async token =>
        {
            addresses = await Dns.GetHostAddressesAsync(host, token);
            return string.Join(',', addresses.Select(address => address.ToString()));
        }, cancellationToken);

        var address = addresses.FirstOrDefault(candidate => candidate.AddressFamily == AddressFamily.InterNetwork)
            ?? addresses.FirstOrDefault();
        if (address is not null)
        {
            await MeasureAsync(stages, "tcp+tls", async token =>
            {
                using var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                var watch = Stopwatch.StartNew();
                await socket.ConnectAsync(new IPEndPoint(address, builder.Port), token);
                var connected = watch.ElapsedMilliseconds;
                await using var network = new NetworkStream(socket, ownsSocket: false);
                await network.WriteAsync(new byte[] { 0, 0, 0, 8, 4, 0xd2, 0x16, 0x2f }, token);
                var answer = new byte[1];
                await network.ReadExactlyAsync(answer, token);
                var negotiated = watch.ElapsedMilliseconds;
                await using var ssl = new SslStream(network, leaveInnerStreamOpen: true);
                await ssl.AuthenticateAsClientAsync(new SslClientAuthenticationOptions
                {
                    TargetHost = host,
                    CertificateRevocationCheckMode = System.Security.Cryptography.X509Certificates.X509RevocationMode.Online,
                    CertificateChainPolicy = PostgresTlsPolicy.CreateChainPolicy()
                }, token);
                return $"connectMs={connected} sslRequestMs={negotiated - connected} " +
                       $"tlsMs={watch.ElapsedMilliseconds - negotiated} answer={(char)answer[0]} protocol={ssl.SslProtocol}";
            }, cancellationToken);
        }

        string? password = null;
        if (!string.Equals(configuration["Postgres:Authentication"], "Password", StringComparison.OrdinalIgnoreCase))
        {
            await MeasureAsync(stages, "token", async token =>
            {
                var accessToken = await credential.GetTokenAsync(
                    new TokenRequestContext(["https://ossrdbms-aad.database.windows.net/.default"]), token);
                password = accessToken.Token;
                return $"expiresOn={accessToken.ExpiresOn:O}";
            }, cancellationToken);
        }

        await MeasureAsync(stages, "npgsql-physical-open", async token =>
        {
            var physical = new NpgsqlConnectionStringBuilder(pooledDataSource.ConnectionString)
            {
                Pooling = false,
                Timeout = 30,
                ApplicationName = "csl-open-diagnostics"
            };
            if (password is not null)
            {
                physical.Password = password;
            }

            var physicalBuilder = new NpgsqlDataSourceBuilder(physical.ConnectionString);
            physicalBuilder.UseSslClientAuthenticationOptionsCallback(options =>
            {
                options.CertificateRevocationCheckMode = System.Security.Cryptography.X509Certificates.X509RevocationMode.Online;
                options.CertificateChainPolicy = PostgresTlsPolicy.CreateChainPolicy();
            });
            await using var dataSource = physicalBuilder.Build();
            await using var connection = await dataSource.OpenConnectionAsync(token);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(token);
            return "ok";
        }, cancellationToken);

        await MeasureAsync(stages, "npgsql-pooled-open", async token =>
        {
            await using var connection = await pooledDataSource.OpenConnectionAsync(token);
            await using var command = new NpgsqlCommand("SELECT 1", connection);
            await command.ExecuteScalarAsync(token);
            return "ok";
        }, cancellationToken);

        password = null;
        stages.Add(new { stage = "runtime-after", detail = RuntimeSnapshot.Describe() });
        return stages;
    }

    private static async Task MeasureAsync(
        List<object> stages,
        string stage,
        Func<CancellationToken, Task<string>> action,
        CancellationToken cancellationToken)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(StageTimeout);
        var watch = Stopwatch.StartNew();
        try
        {
            var detail = await action(timeout.Token);
            stages.Add(new { stage, elapsedMs = watch.ElapsedMilliseconds, status = "ok", detail });
        }
        catch (Exception exception)
        {
            stages.Add(new
            {
                stage,
                elapsedMs = watch.ElapsedMilliseconds,
                status = "error",
                detail = $"{exception.GetType().FullName}: {exception.GetBaseException().Message}"
            });
        }
    }
}
