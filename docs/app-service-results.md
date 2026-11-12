# App Service results

[Executive summary](executive-summary.md) | [Method](method.md) | Previous: [AKS results](aks-results.md)

App Service manages the workers, and Chaos Studio can kill the application process on chosen workers. This deployment ran the application without a read cache, so the database failover shows what clients see when every read depends on the current primary.

## Architecture

![App Service architecture](diagrams/04-private-linux-app-service.svg)

The P1v3 plan used `zoneRedundant=true` and six fixed workers in Spain Central, two in each zone. Clients reached the app through a Private Endpoint; outbound VNet Integration reached PostgreSQL 16 with zone-redundant HA. Chaos Studio's *Kill process* Action supports Windows App Service plans, so the process tests ran on a Windows variant (.NET 9) with the same plan shape, private paths and database. On the Linux variant, the database failover gave the same picture: 97.62% business success and 32.3 seconds recovery.

## Results

The measurements ran on 6 November 2026.

| Phase | Successful business ops | Failed | Dropped | Business success | p95 | Recovery |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline, 10 min | 12,001 | 0 | 0 | 100% | 123 ms | |
| Kill process on one exact worker, 12 min | 14,401 | 0 | 0 | 100% | 122 ms | |
| Kill process on both workers in one zone, 12 min | 14,401 | 0 | 0 | 100% | 121 ms | |
| PostgreSQL forced failover, 18 min | 21,028 | 414 | 159 | 97.347% | 123 ms | 36.4 s |
| Failover plus process kill, 18 min | 21,023 | 429 | 149 | 97.324% | 121 ms | 35.0 s |

After a process kill, App Service started a replacement process on the same worker 11–13 seconds later, and no client request failed because the other workers kept serving. During the database failover every worker depends on the same primary, so all of them returned errors until connections reached the promoted standby. Service recovered in about 35 seconds and stayed stable, and the errors concentrated in that interval bring the 18-minute business success to 97.3%. In the combined case, database errors observed independently bracketed every process replacement, so the two faults overlapped.

Reconciliation found all 22,424 acknowledged writes from these phases and their warmup, each with its expected checksum.

## Lesson

Npgsql 10 defaults to `GssEncryptionMode.Prefer`, which probes Kerberos/SSPI before each physical connection. On Windows App Service that probe took 4.7–5.1 seconds and exceeded the 3-second database deadline. Setting `GssEncryptionMode.Disable` brought physical connection opens to 0.22–0.60 seconds, with VerifyFull TLS and Entra tokens unchanged.
