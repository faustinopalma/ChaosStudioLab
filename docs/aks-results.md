# AKS results

[Executive summary](executive-summary.md) | [Method](method.md) | Previous: [Container Apps results](container-apps-results.md) | Next: [App Service results](app-service-results.md)

AKS exposes the virtual machines under the workload, so Chaos Studio can remove real compute capacity: one exact node, or every lab-owned node in one zone, for at least five continuous minutes.

## Architecture

![AKS architecture](diagrams/06-private-aks-zone-lab.svg)

The Sweden Central cluster (AKS 1.35.9, Azure Linux 3.0, Standard tier) has three system nodes and six single-node user pools, two per zone, with autoscaling disabled so capacity stays fixed. Six .NET 10 pods run one per user node. Clients reach them through a private internal load balancer with `externalTrafficPolicy: Local` and a 5-second, two-probe health check. PostgreSQL 16 uses zone-redundant HA.

Single-node pools make the fault precise: shutting down pool `z1a` removes exactly one application pod, and shutting down the zone-1 system pool together with `z1a` and `z1b` removes all lab compute in zone 1, while four pods in zones 2 and 3 keep serving.

## Results by configuration

Each measurement exposed a configuration gap, which we fixed before the next one. The table shows business success over the 18-minute phase, the first five minutes after a node shutdown in brackets, and the recovery time from the observed effect.

| Configuration | Change | One node shut down | Zone-1 lab nodes shut down | PostgreSQL failover | Failover plus zone-1 shutdown |
| --- | --- | --- | --- | --- | --- |
| Initial | none | 99.55% (98.95%), recovery 39 s | 98.96% (97.85%), recovery 64 s | 98.01%, recovery 29 s | 97.44%, recovery 29 s |
| Revision 1 | one pod per node, local routing, HTTP/1.1, per-pod read cache | 99.963% (100%), recovery < 1 s | 99.949% (100%), recovery < 1 s | 99.38%, recovery 33 s | not measured |
| Revision 2 | shared Redis read cache | not measured | not measured | 99.76%, recovery 27 s | not measured |

With revision 1, one node stayed powered off for at least 304 seconds and three zone-1 nodes for at least 305 seconds. The first five minutes after each shutdown had 100% business success with a 10 ms p95, and across 18 minutes only 8 and 11 business operations failed, all in the transition. Six pods returned to six distinct workers in three zones without manual action.

With revision 2, the database failover produced no failed business operation: 332 attempts failed and were retried until PostgreSQL confirmed them, with a 13 ms p95. The load generator dropped 51 scheduled operations in a 15-second interval while it was creating virtual users, which brings the phase to 99.76%.

Reconciliation in PostgreSQL, bypassing both caches, found all 68,245 acknowledged writes across the 18 measured runs.

## Lessons

- **Require one pod per node and route only to local pods.** With soft spreading, a rescheduled pod landed beside another and left five workers for six pods. Hard anti-affinity keeps the replacement Pending until its node returns, and `externalTrafficPolicy: Local` with fast health probes keeps the load balancer from sending traffic to a stopped node.
- **Check how clients handle connections to a lost node.** In the initial configuration, node loss produced recurring 8-second client timeouts. After switching ingress to HTTP/1.1 and adding the per-pod cache, failed attempts during node loss fell from 458 to 10; the two changes were made together.
- **Share confirmed reads across replicas.** With per-pod caches, reads failed during a database failover on pods that had never seen the requested order. A shared cache removed those failures.
- **Preallocate the load generator.** Creating virtual users during the failover dropped 51 scheduled operations. The Container Apps runs preallocated 200 + 10 virtual users and dropped none.

The shutdowns stop tenant virtual machines while the load balancer, PostgreSQL and Redis keep running, so these results describe compute loss.
