# Method

[Executive summary](executive-summary.md) | [App Service](app-service-results.md) | [AKS](aks-results.md) | [Container Apps](container-apps-results.md)

Every platform ran the same order API, the same workload and the same acceptance gates. This page describes them once.

## The application and its write contract

The API stores orders in PostgreSQL. A client sends an operation ID and a payload; the API acknowledges only after PostgreSQL commits, and returns the payload's SHA-256 checksum. Repeating the same operation ID returns the stored order, and a different payload under the same ID returns a conflict. This makes retries safe and lets us check durability exactly: after each run, a direct SQL snapshot must contain every acknowledged operation ID with the checksum the client expected. The AKS and Container Apps versions also read SQL-confirmed immutable orders from a local cache and a shared Azure Managed Redis cache; writes and the durability check always go to PostgreSQL.

## The workload

A private runner uses k6 to schedule 20 business operations per second, 80% reads and 20% writes, plus one independent read/write canary per second. Each HTTP attempt has an 8-second deadline, and a write is retried with the same operation ID for up to 180 seconds. The runner preallocates 200 business and 10 canary virtual users so that capacity is ready before a fault. A scheduled operation that finds no free virtual user is recorded as a *drop* and counts as a failure.

Each fault case runs 18 minutes: about 45 seconds of steady load, the injection, and at least 10 minutes of recovery. A 5-minute warmup and a 10-minute baseline must pass first.

## Fault mechanisms

| Fault | App Service | AKS | Container Apps |
| --- | --- | --- | --- |
| Application capacity | Native *Kill process* on one exact worker, or on both workers in one zone | Native VMSS shutdown of one exact node, or of the three lab nodes in one zone, for at least 300 s | Lab adapter withdraws 2 of 6 replicas from readiness for 360 s (no native fault exists) |
| Database | Native PostgreSQL ForcedFailover | same | same |
| Combined | Database failover first; the application fault starts once the runner observes database errors | same | same |
| Whole zone | BLOCKED | BLOCKED | BLOCKED |

Chaos Studio reports when an Action was accepted and completed. The lab adds independent evidence of the effect: a dependency probe every second, Azure Resource Manager power states or replica readiness every 5 seconds, the PostgreSQL primary and standby zones before and after, and Activity Log caller claims that tie the operation to the Workspace identity.

## Acceptance gates

| Gate | Requirement |
| --- | --- |
| Baseline and stable period | 99.9% business success, successful-operation p95 at most 1 s |
| Application capacity fault | First 300 s after the effect: 99% business success, p95 at most 2 s, no canary outage longer than 5 s |
| Database or combined fault | A complete 60-second window at 99% success begins within 180 s of the observed disruption, followed by 300 stable seconds; 18-minute availability at 99.9% |
| Durability | Every acknowledged write present in SQL with its expected checksum |

The *p95 latency* is the time within which 95% of successful operations completed; failures and drops are counted separately. Recovery and availability are reported separately, because a service can recover in 30 seconds and still miss an availability target over 18 minutes.

Each case ends with one of four verdicts. PASS means every gate passed with complete evidence. FAIL means a measured gate missed its threshold. BLOCKED means the fault could not be injected or qualified. INCONCLUSIVE means the effect happened but the evidence needed for a verdict is incomplete.

## What these tests cover

*High availability* (HA) is the ability to keep serving, or recover automatically, when a component fails. *Disaster recovery* (DR) is the ability to restore service and data after a broader loss, such as a zone or a region, measured as a recovery time objective (RTO) and a recovery point objective (RPO).

The faults above remove application processes, compute capacity or the database primary while the rest of the region keeps running. They are HA tests. A DR test needs a different exercise: a real zone or regional failover, or a backup restore, with service and data recovery measured on the intended path. None of the platforms offered a Chaos Studio fault that takes down a whole zone, including its managed services, so the whole-zone case stayed BLOCKED.

## Private context

Tenant and subscription IDs, accounts, resource names, credentials and raw evidence stay in the ignored `.local\` and `.azure\` folders. Run `pwsh .\tests\Test-Publication.ps1` before committing; it checks ignored paths and searches tracked files for known private values.
