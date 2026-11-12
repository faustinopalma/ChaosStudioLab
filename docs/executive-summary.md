# Executive summary: HA testing with Azure Chaos Studio

[README](../README.md) | Details: [Method](method.md) · [Container Apps](container-apps-results.md) · [AKS](aks-results.md) · [App Service](app-service-results.md)

We used Azure Chaos Studio to test *high availability* (HA): the ability of an application to keep serving, or recover automatically, when a component fails. One order API, which acknowledges a write only after PostgreSQL commits it, ran on Azure Container Apps, AKS and App Service between 4 and 11 November 2026, under the same load and the same measurements.

These results come from a single laboratory exercise with one application, one load profile and specific configurations. They describe how this design behaved; Azure availability commitments are defined in the [Azure SLAs](https://aka.ms/CSLA).

## 1. Findings

All three platforms absorbed the loss of application capacity. In their final configurations, losing two of six Container Apps replicas, one AKS node, all lab nodes in one zone, or the application process on App Service workers cost at most 11 business operations per fault phase of 14,400 to 21,600.

Service recovered 27–36 seconds after every PostgreSQL zone-redundant failover, and no acknowledged write was lost. What clients saw during those seconds depended on the application. On every platform the client retried writes with the same operation ID, so the difference was in reads, which are 80% of the traffic. The Container Apps and AKS build served already-confirmed orders from a shared cache and no business operation failed. The App Service build had no read cache: 97.3% of business operations completed, and the errors were concentrated in the role change.

The faults were most useful for finding gaps in our own configuration that health checks alone did not show. The initial AKS configuration lost 1.1% (one node) and 2.2% (zone-1 nodes) of business operations in the first five minutes after a shutdown; pod anti-affinity, node-local routing, HTTP/1.1 and caching brought those minutes to 100%.

## 2. The three architectures

Every platform used the same private design: a private runner generating load, private ingress, PostgreSQL 16 with zone-redundant HA, Key Vault and the registry behind private endpoints, and Entra identities instead of passwords. Container Apps and AKS ran in Sweden Central, App Service in Spain Central.

**Container Apps** ran six fixed replicas in an internal zone-redundant environment, with the cached build. Chaos Studio has no Container Apps fault, so a lab adapter withdrew replicas from readiness.

![Container Apps architecture](diagrams/07-private-container-apps.svg)

**AKS** ran six pods on six single-node pools, two per zone, behind an internal load balancer with node-local routing. Chaos Studio shut down one exact node or all lab nodes in one zone. Reads of confirmed orders used a per-pod cache and a shared Azure Managed Redis.

![AKS architecture](diagrams/06-private-aks-zone-lab.svg)

**App Service** ran six P1v3 workers, two per zone, with Private Endpoint ingress and VNet Integration egress, and no read cache. Chaos Studio's process fault supports Windows plans, so the tests used a Windows variant.

![App Service architecture](diagrams/04-private-linux-app-service.svg)

## 3. Results

Business success is measured over the whole fault phase: 18 minutes, or 12 minutes for the App Service process kills. Recovery is the time from the first observed database error to the first full minute with at least 99% success.

| Fault | Container Apps | AKS | App Service (Windows) |
| --- | --- | --- | --- |
| Application capacity | 2 of 6 replicas withdrawn for 346 s: 100% | Shutdown of one node / of all zone-1 lab nodes: 99.96% / 99.95%; first five minutes 100% | Process kill on one worker, or on both workers of one zone: 100% |
| PostgreSQL failover | 100%, recovery 35 s | 99.76% (0 failed, 51 dropped), recovery 27 s | 97.35%, recovery 36 s |
| Failover plus capacity fault | 100%, recovery 28 s | 97.44%, recovery 29 s (initial configuration, without cache) | 97.32%, recovery 35 s |
| Acknowledged writes lost | 0 of 20,689 | 0 of 68,245 | 0 of 22,424 |

Two facts are needed to read this table. First, the database results compare application designs more than platforms: Container Apps and AKS ran the cached build, while App Service ran without a cache. Second, the capacity faults differ in severity. A node shutdown on AKS removes a host abruptly and is the strongest test; a readiness withdrawal on Container Apps and a process kill on App Service leave the host running, and the withdrawal also lets in-flight requests finish.

## 4. What Chaos Studio covered

Native Actions gave repeatable, precisely targeted faults: PostgreSQL forced failover on every platform, scale-set shutdown on AKS, and process kill on Windows App Service. Chaos Studio's [supported resources](https://learn.microsoft.com/azure/chaos-studio/chaos-studio-workspaces-supported-resources) include no Container Apps Action, so we followed the [Container Apps reliability guidance](https://learn.microsoft.com/azure/reliability/reliability-container-apps) and simulated replica loss at the application layer by failing the readiness endpoint.

## 5. Next steps

The lab covered HA for component faults. Disaster recovery, meaning restoring service in another region or from backup with measured RTO and RPO, needs its own exercise. Useful next HA tests are an abrupt replica crash on Container Apps, all AKS faults on a single configuration, and a shared-cache outage.
