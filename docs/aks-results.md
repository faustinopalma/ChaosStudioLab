# AKS results

[Executive summary](executive-summary.md) | [Method](method.md) | Previous: [App Service results](app-service-results.md) | Next: [Container Apps results](container-apps-results.md)

App Service only let us crash processes. To remove real compute capacity we moved the same application to AKS, where Chaos Studio can shut down the virtual machines under the workload: one exact node, or every lab-owned node in one zone, for at least five continuous minutes.

## Architecture

![AKS architecture](diagrams/06-private-aks-zone-lab.svg)

The Sweden Central cluster (AKS 1.35.9, Azure Linux 3.0, Standard tier) has three system nodes and six single-node user pools, two per zone, with autoscaling disabled so capacity stays fixed. Six .NET 10 pods run one per user node, enforced by hard hostname anti-affinity. Clients reach them through a private internal load balancer with `externalTrafficPolicy: Local` and a 5-second, two-probe health check. PostgreSQL 16 uses zone-redundant HA. The last version also reads SQL-confirmed immutable orders from a bounded local cache and a private HA Azure Managed Redis before querying PostgreSQL; every write still commits in PostgreSQL first.

The single-node pools make the fault precise. Shutting down pool `z1a` removes exactly one application pod; shutting down the zone-1 system pool and `z1a`/`z1b` removes all lab compute in zone 1, while four pods in zones 2 and 3 keep serving.

## How the results improved

The first run exposed real weaknesses, and each was fixed before the next measurement. The table shows business success over the 18-minute phase, with the first five minutes after a node shutdown in brackets, and the recovery time from the observed effect.

| Version | Change | One node shut down | Zone-1 lab nodes shut down | PostgreSQL failover | Failover plus zone-1 shutdown |
| --- | --- | --- | --- | --- | --- |
| Original | none | 99.55% (98.95%), recovery 39 s | 98.96% (97.85%), recovery 64 s | 98.01%, recovery 29 s | 97.44%, recovery 29 s |
| Repair 1 | one pod per host, Local routing, HTTP/1.1, per-pod read cache | 99.963% (100%), recovery < 1 s | 99.949% (100%), recovery < 1 s | 99.38%, recovery 33 s | not measured |
| Repair 2 | shared Redis read cache | not measured | not measured | 99.76%, recovery 27 s | not measured |

Let's read it with the best results first. With repair 1, an exact node stayed powered off for at least 304 seconds and three zone-1 nodes for at least 305 seconds. In both cases the first five minutes after the shutdown had 100% business success and a 10 ms p95; across 18 minutes only 8 (node) and 11 (zone) business operations failed, all in the transition. Service reached a full minute at 99% success within one second of the observed power-off, and six pods returned to six distinct workers in three zones without manual action.

With repair 2, the database failover produced no failed business operation: 332 attempts failed and were retried until PostgreSQL confirmed them, and the p95 was 13 ms. The load generator dropped 51 scheduled operations in a 15-second interval while it was creating virtual users, which brings the phase to 99.76%. Repair 2 was measured only against the database failover.

Direct PostgreSQL reconciliation, bypassing both caches, found all 68,245 acknowledged writes across the 18 runs up to the last reported case.

## Findings worth keeping

- **One pod per node and node-local routing.** In the original run, a rescheduled pod landed beside another, leaving five workers for six pods. Hard anti-affinity keeps the replacement Pending until its node returns, and `externalTrafficPolicy: Local` with fast health probes stops the load balancer from forwarding to a dead node.
- **HTTP/2 connections lingered on dead nodes.** Node loss produced recurring 8-second transport failures; with HTTP/1.1 and the per-pod cache, failed attempts during node loss fell from 458 to 10. The two changes were made together, so their individual effect is unmeasured.
- **Cold replicas need a shared cache during failover.** With per-pod caches, reads failed on pods that had never seen the requested order. The shared Redis layer removed those failures.
- **Load generators must preallocate.** k6 created virtual users during the failover and dropped 51 scheduled operations. The Container Apps runs preallocated 200 + 10 virtual users and dropped no business operation.
- **Defender for Containers created a public telemetry workspace.** Enabling the cluster's security profile caused Defender to create a default Log Analytics workspace, with public ingestion and query, outside the lab's resource groups. Private workload paths remained private, but security telemetry did not.

## What the evidence supports

AKS with one pod per node, local routing and HTTP/1.1 absorbs the sudden loss of one node or of all lab nodes in one zone with at most 11 failed operations out of 21,600. With a shared cache for confirmed reads, PostgreSQL failover no longer causes business errors. The shutdowns stop tenant virtual machines while the managed load balancer, PostgreSQL and Redis keep running, so these are compute-loss tests.
