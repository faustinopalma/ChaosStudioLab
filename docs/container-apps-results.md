# Container Apps results

[Executive summary](executive-summary.md) | [Method](method.md) | Previous: [AKS results](aks-results.md)

Container Apps runs containers without exposing nodes, so the questions change slightly. We cannot shut down a host, and Chaos Studio has no fault for Container Apps. What we can test is whether the platform stops routing to replicas that report themselves unhealthy, whether the remaining replicas absorb the load, and how the application behaves when PostgreSQL fails over, alone or at the same time.

## Architecture

![Container Apps architecture](diagrams/07-private-container-apps.svg)

The lab ran on 11 November 2026 in Sweden Central. An internal Container Apps environment with `zoneRedundant=true` and the Consumption workload profile sits in a delegated /23 subnet; its static private IP is published through a private DNS zone for the environment's default domain. One container app runs six fixed replicas (minimum and maximum 6, 1 vCPU and 2 GiB each) from a digest-pinned image in a private Premium registry. Azure spreads the replicas across the three zones and does not report which zone each replica uses.

The application is the same .NET 10 build used on AKS, including the local and shared Redis caches for SQL-confirmed orders. Dependencies are private: PostgreSQL 16 with zone-redundant HA (primary zone 1, standby zone 2), Azure Managed Redis with HA, Key Vault and the registry, each behind a private endpoint, with Entra authentication through one user-assigned identity.

## The replica fault

A Container Apps *readiness probe* tells the ingress whether a replica may receive traffic. Ours calls `/health/serving`, which checks only the process and a lab *fault lease*: an in-memory flag, set through an authenticated endpoint, that makes the probe return 503 for a fixed time and then clears itself. The probe ignores PostgreSQL on purpose, so a database failover leaves all replicas in rotation and the application handles the errors itself.

To remove capacity, the runner calls the fault endpoint through the ingress until two distinct replicas have accepted a 360-second lease. With probes every 2 seconds and two failures required, those replicas leave rotation within seconds while their processes keep running. Azure Resource Manager reports each replica's readiness, so an independent observer can confirm which replicas were withdrawn and for how long.

## Results

| Phase | Business ops OK | Failed ops | Failed attempts, retried | Drops | Canary OK / dropped | p95 | Recovery |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Baseline, 10 min | 12,001 | 0 | 0 | 0 | 600 / 0 | 28 ms | |
| Two of six replicas withdrawn, 18 min | 21,600 | 0 | 0 | 0 | 1,081 / 0 | 28 ms | |
| PostgreSQL forced failover, 18 min | 21,601 | 0 | 561 | 0 | 1,055 / 25 | 30 ms | 35.2 s |
| Failover plus replica withdrawal, 18 min | 21,601 | 0 | 350 | 0 | 1,063 / 18 | 29 ms | 27.6 s |

Let's read the replica case first. The observer saw both target replicas unready and the four others ready for 345.7 seconds without interruption, and no successful request came from a withdrawn replica in that interval. Clients saw nothing: across 18 minutes there was not a single failed attempt, and the first five minutes after the withdrawal had 100% success with a 29 ms p95.

The database cases show the cache design at work. During the failover the dependency probe returned 503 for about 35 seconds, and 561 individual attempts failed, but every one was retried until PostgreSQL confirmed it, so no business operation failed and none was dropped. Reads of already-confirmed orders kept coming from the caches. The primary moved from zone 1 to zone 2 and back again in the combined run, with HA healthy afterwards. In the combined case the replica withdrawal started at 15:00:25.027 UTC, between database errors observed at 15:00:24.064 and 15:00:25.085, which proves the two faults overlapped.

The canary dropped 25 and 18 scheduled checks during the failovers. Each canary performs a confirmed write; when every write waits on the database, its 10 virtual users are all busy and the next scheduled check has no user to run on. The business workload, with 200 virtual users, dropped nothing.

Direct PostgreSQL reconciliation found all 20,689 acknowledged writes from these five runs, including the warmup, each with its expected checksum.

## Findings worth keeping

- **Withdrawal is graceful.** Replicas left rotation within about 13 seconds of the call with zero failed requests, because the probe changes routing while in-flight requests complete normally.
- **Probes with a 1-second timeout occasionally fail under load.** One unrelated replica reported unready for a single 5-second sample, without restart or client impact.

## What the evidence supports

With six replicas, a database-independent readiness probe and SQL-confirmed caching, Container Apps kept 100% business success when a third of its capacity left rotation, when PostgreSQL failed over, and when both happened together. The replica fault is gentler than a crash or a node loss: the processes stay alive and drain in-flight work. An abrupt replica crash remains untested.

The infrastructure deployment took 24 minutes; all build stages together, including image build, private checks and inventory recording, took 77 minutes. The four measured cases took about 1 hour 45 minutes. The lab's resource groups were deleted after the measurements.
