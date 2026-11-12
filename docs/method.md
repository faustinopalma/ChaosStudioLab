# Method

[Executive summary](executive-summary.md) | [Container Apps](container-apps-results.md) | [AKS](aks-results.md) | [App Service](app-service-results.md)

Every platform ran the same application, workload and measurements.

## Application and write contract

The API stores orders in PostgreSQL. A client sends an operation ID and a payload; the API acknowledges only after PostgreSQL commits, and returns the payload's SHA-256 checksum. Repeating an operation ID returns the stored order, and a different payload under the same ID returns a conflict. Retries are therefore safe, and durability can be checked exactly: after each run, a PostgreSQL snapshot must contain every acknowledged operation ID with the expected checksum. The Container Apps and AKS build also reads confirmed orders from a local cache and a shared Azure Managed Redis; writes and the durability check always go to PostgreSQL.

## Workload

A private runner uses k6 to schedule 20 business operations per second, 80% reads and 20% writes, plus one read/write canary per second. Each HTTP attempt has an 8-second deadline, and a write is retried with the same operation ID for up to 180 seconds. A scheduled operation that finds no free virtual user is recorded as a *drop*; the final configuration preallocates 200 business and 10 canary virtual users.

Each fault case runs 18 minutes (12 minutes for the App Service process kills): about 45 seconds of steady load, the injection, and at least 10 minutes of recovery. A 5-minute warmup and a 10-minute baseline run first on every deployed version.

## Faults

| Fault | Container Apps | AKS | App Service |
| --- | --- | --- | --- |
| Application capacity | Lab adapter withdraws 2 of 6 replicas from readiness for 360 s | Native VMSS shutdown of one exact node, or of the three lab nodes in one zone, for at least 300 s | Native *Kill process* on one exact worker, or on both workers in one zone |
| Database | Native PostgreSQL ForcedFailover | same | same |
| Combined | Database failover first; the capacity fault starts once the runner observes database errors | same | same |

Chaos Studio reports when an Action was accepted and completed. The runner adds its own evidence of the effect: a dependency probe every second, replica readiness or VM power state every 5 seconds, and the PostgreSQL primary and standby zones before and after. A run is reported only when this evidence confirms the intended effect for its whole duration; runs with incomplete evidence are discarded.

## Metrics

| Metric | Definition |
| --- | --- |
| Business success | Successful operations divided by successful, failed and dropped operations over the whole phase. A write retried to success counts once as successful |
| First five minutes | Business success over the 300 seconds after the observed capacity loss |
| Successful-operation p95 | The time within which 95% of successful operations completed |
| Recovery time | Time from the observed effect (the first database error, or the first power-off sample of a node shutdown) to the start of the first complete 60-second window with at least 99% business and canary success and p95 at most 1 s |
| Durability | Acknowledged writes missing from PostgreSQL, or stored with a different checksum |
