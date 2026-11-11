# Executive summary: HA and DR with Azure Chaos Studio

[README](../README.md) | Details: [Method](method.md) · [App Service](app-service-results.md) · [AKS](aks-results.md) · [Container Apps](container-apps-results.md)

The goal was to use Azure Chaos Studio to test *high availability* (HA), the ability to keep serving or recover automatically when a component fails, and *disaster recovery* (DR), the ability to restore service and data after a broader loss. We ran one order API, which acknowledges a write only after PostgreSQL commits it, on three Azure platforms between 4 and 11 November 2026, under the same load and the same acceptance gates.

## 1. Conclusion

All three platforms survived the loss of application capacity with almost no client impact, and no acknowledged write was lost in any run: 92,616 on App Service, 78,142 on AKS and 26,264 on Container Apps. The decisive factor for database failover was the application design. Without a cache, App Service lost about 2.7% of business operations, as failures or drops, during the 18-minute failover phase; with SQL-confirmed caching and retries, AKS and Container Apps completed every business operation.

Container Apps is the only platform where the complete suite passed on a single version: baseline, replica withdrawal, PostgreSQL failover and the combined fault. On AKS the best version passed node and zone-compute shutdown, and a later version passed the database business gate, but no single version ran the whole suite.

DR remains untested. Chaos Studio has no fault that removes a whole availability zone together with its managed services, and the lab ran no regional failover or backup restore. The results support HA conclusions for the specific faults we injected.

## 2. The three architectures

Every platform used the same private design: a private runner generating load, private ingress, PostgreSQL 16 with zone-redundant HA, Key Vault and the registry behind private endpoints, and Entra identities instead of passwords.

**App Service** ran six P1v3 workers, two per zone, with Private Endpoint ingress and VNet Integration egress, and no read cache. Linux rejected Chaos Studio's process fault, so the tests used a Windows variant.

![App Service architecture](diagrams/04-private-linux-app-service.svg)

**AKS** ran six pods on six single-node pools, two per zone, behind an internal load balancer with node-local routing. Chaos Studio could shut down one exact node or all lab nodes in one zone. Reads of confirmed orders used a per-pod cache and a shared Azure Managed Redis.

![AKS architecture](diagrams/06-private-aks-zone-lab.svg)

**Container Apps** ran six fixed replicas in an internal zone-redundant environment, with the AKS application and caches unchanged. Chaos Studio has no Container Apps fault, so a lab adapter withdrew replicas from readiness.

![Container Apps architecture](diagrams/07-private-container-apps.svg)

## 3. Results

The table shows the best qualified result for each platform and fault. Business success is measured over the whole 18-minute fault phase unless noted.

| Fault | App Service (Windows) | AKS | Container Apps |
| --- | --- | --- | --- |
| Application capacity | Process kill on one worker or a whole zone's workers: 100%, PASS | Shutdown of one node or all zone-1 lab nodes: first 5 min 100%, phase 99.96% / 99.95%, PASS | 2 of 6 replicas withdrawn for 346 s: 100%, PASS |
| PostgreSQL failover | 97.35%, recovery 36 s, availability FAIL | 100% business, overall INCONCLUSIVE (observer gap) | 100%, recovery 35 s, PASS |
| Failover plus capacity fault | 97.32%, recovery 35 s, availability FAIL | Repaired version not run | 100%, recovery 28 s, PASS |
| Whole-zone outage | BLOCKED | BLOCKED | BLOCKED |

Two facts are needed to read this table fairly. First, the database results compare application designs more than platforms: AKS and Container Apps ran the cached build that the AKS investigation produced, while App Service ran without a cache. Second, the capacity faults differ in severity. A node shutdown on AKS removes a host abruptly and is the strongest test; a process kill on App Service and a readiness withdrawal on Container Apps leave the host running, and the withdrawal also lets in-flight requests finish.

## 4. Where Chaos Studio helped

Chaos Studio's native faults gave repeatable, precisely targeted tests: the PostgreSQL forced failover on every platform, VMSS shutdown on AKS, and process kill on Windows App Service. Combined with independent observation, they exposed real weaknesses that healthy dashboards hid: HTTP/2 connections lingering on dead AKS nodes, pods doubling up on one node, cold caches during failover, and load generators creating virtual users too late.

Coverage stopped in three places. Linux App Service could not run the process fault. Container Apps has no native fault, so its capacity test relied on our own readiness adapter. No platform offered a whole-zone fault that also takes down managed services such as the load balancer, PostgreSQL or Redis.

## 5. HA, DR and next steps

The evidence supports these HA conclusions: losing a third of application capacity, one node or one zone's compute does not interrupt clients when capacity is pre-provisioned and routing follows health; a PostgreSQL zone-redundant failover recovers within 27–36 seconds without data loss; and SQL-confirmed caching with idempotent retries hides that failover from the business workload.

A DR exercise needs a separate design: a recovery region or restore target, data replication or backup, traffic redirection, and measured RTO and RPO. The next HA steps are an abrupt replica-crash test on Container Apps, a single-version AKS rerun of all faults, and a cache-outage test now that both container platforms depend on Redis.
