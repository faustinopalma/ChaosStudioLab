# Method

[Executive summary](executive-summary.md) | [App Service](app-service-results.md) | [AKS](aks-results.md) | [Container Apps](container-apps-results.md)

Every platform ran the same order API, the same workload and the same measurements. This page describes them once.

## The application and its write contract

The API stores orders in PostgreSQL. A client sends an operation ID and a payload; the API acknowledges only after PostgreSQL commits, and returns the payload's SHA-256 checksum. Repeating the same operation ID returns the stored order, and a different payload under the same ID returns a conflict. This makes retries safe and lets us check durability exactly: after each run, a direct SQL snapshot must contain every acknowledged operation ID with the checksum the client expected. The AKS and Container Apps versions also read SQL-confirmed immutable orders from a local cache and a shared Azure Managed Redis cache; writes and the durability check always go to PostgreSQL.

## The workload

A private runner uses k6 to schedule 20 business operations per second, 80% reads and 20% writes, plus one independent read/write canary per second. Each HTTP attempt has an 8-second deadline, and a write is retried with the same operation ID for up to 180 seconds. A scheduled operation that finds no free virtual user is recorded as a *drop*. The final configuration preallocates 200 business and 10 canary virtual users so that capacity is ready before a fault.

Each fault case runs 18 minutes (12 minutes for the App Service process kills): about 45 seconds of steady load, the injection, and at least 10 minutes of recovery. A 5-minute warmup and a 10-minute baseline run first on every deployed version.

## Fault mechanisms

| Fault | App Service | AKS | Container Apps |
| --- | --- | --- | --- |
| Application capacity | Native *Kill process* on one exact worker, or on both workers in one zone | Native VMSS shutdown of one exact node, or of the three lab nodes in one zone, for at least 300 s | Lab adapter withdraws 2 of 6 replicas from readiness for 360 s (no native fault exists) |
| Database | Native PostgreSQL ForcedFailover | same | same |
| Combined | Database failover first; the application fault starts once the runner observes database errors | same | same |

Chaos Studio reports when an Action was accepted and completed. The lab adds independent evidence of the effect: a dependency probe every second, Azure Resource Manager power states or replica readiness every 5 seconds, the PostgreSQL primary and standby zones before and after, and Activity Log caller claims that tie the operation to the Workspace identity. A run is reported only when this evidence confirms the intended effect for its whole duration and every observer covered the whole phase; runs with incomplete evidence are discarded.

## Metrics

| Metric | Definition |
| --- | --- |
| Business success | Successful operations divided by successful, failed and dropped operations over the whole phase. A write retried to success counts once as successful |
| First five minutes | Business success over the 300 seconds after the observed capacity loss |
| Successful-operation p95 | The time within which 95% of successful operations completed |
| Recovery time | Time from the observed effect (the first database error, or the first power-off sample of a node shutdown) to the start of the first complete 60-second window with at least 99% business and canary success and p95 at most 1 s |
| Durability | Acknowledged writes missing from the direct PostgreSQL snapshot, or stored with a different checksum |

## What these tests cover

*High availability* (HA) is the ability to keep serving, or recover automatically, when a component fails. *Disaster recovery* (DR) is the ability to restore service and data after a broader loss, measured as a recovery time objective (RTO) and a recovery point objective (RPO).

The faults above remove application processes, compute capacity or the database primary while the rest of the region keeps running, so they are HA tests. A DR test needs a different exercise: a regional failover or a backup restore, with service and data recovery measured on the intended path.

## Private context

Tenant and subscription IDs, accounts, resource names, credentials and raw evidence stay in the ignored `.local\` and `.azure\` folders. Run `pwsh .\tests\Test-Publication.ps1` before committing; it checks ignored paths and searches tracked files for known private values.
