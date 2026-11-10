# Executive summary: HA and DR with Azure Chaos Studio

[Repository overview](../README.md) | Next: [reading guide](lab-guide.md)

Evidence closed on 7 November 2026. This summary compares the recorded App Service and AKS experiments; it makes no claim about resources still running today.

## 1. Executive conclusion

The objective was to use Azure Chaos Studio to test *high availability (HA)*, the ability to keep serving or recover automatically through component failures, and *disaster recovery (DR)*, the ability to restore service and data after a broader disaster. The laboratory produced useful HA evidence and exposed genuine availability failures. DR remains unvalidated: the work contains no qualified whole-zone disaster, regional failover, or backup-restore exercise.

The clearest positive results are Windows App Service process-crash resilience, repaired AKS node and selected-zone compute resilience, and retention of every acknowledged write checked in both platforms. Database failover recovered automatically in measured cases, but several runs missed the required business-availability target. The last AKS database run reached 100% scheduled business success, while missing topology evidence kept its overall verdict INCONCLUSIVE. The complete repaired AKS suite was never qualified on one final version.

The practical outcome is a bounded set of successful resilience mechanisms, measured failures and evidence gaps. A production HA or DR approval still requires the missing tests.

## 2. The two measured architectures

Both platforms serve an order API that acknowledges a write only after PostgreSQL confirms it. Clients record the operation identifier and expected checksum, so later reconciliation can check acknowledged-write retention. A private runner generates load and observes fault effects independently of the Chaos Studio Action's accepted/completed status.

### App Service: managed workers and private PostgreSQL

![App Service architecture: six workers across three zones, private application ingress, outbound integration, PostgreSQL HA and a separate private runner.](diagrams/04-private-linux-app-service.svg)

[Open the editable App Service diagram](diagrams/04-private-linux-app-service.svg).

The Spain Central workload used six P1v3 App Service workers, observed as two workers in each of three physical zones. Requests entered through a Private Endpoint; outbound VNet Integration reached private PostgreSQL with a primary and standby in different zones. The single private runner and Chaos Workspace operated from Sweden Central. That second region supplied management and measurement; the application and database had no secondary regional recovery deployment.

The Linux variant exposed a fault-injection limitation: native process deletion failed on every tested stack. The Windows comparison therefore used the same private topology to exercise process crashes. App Service replaced each killed application process in place, allowing the other workers to continue serving.

### AKS: explicitly targetable nodes and private PostgreSQL

![AKS architecture: six application workers across three zones, three system nodes, private load balancer, private PostgreSQL HA and shared confirmed-order cache.](diagrams/06-private-aks-zone-lab.svg)

[Open the editable AKS diagram](diagrams/06-private-aks-zone-lab.svg).

The Sweden Central workload used nine nodes: three system nodes and six single-node user pools, with two application workers per zone. Six .NET 10 pods were placed on six distinct workers. Private HTTPS entered through an internal load balancer using Local routing and health probes. Chaos Studio could target an exact node or the three owned nodes in the selected zone, while independent observations verified at least five continuous minutes of power-off.

Repairs added hard pod anti-affinity, routing corrections, HTTP/1.1 and confirmed immutable-order caching. The final architecture reads from a bounded local cache, private HA Azure Managed Redis, then PostgreSQL. Writes and write reconciliation still require PostgreSQL confirmation. The shared cache improves availability for previously confirmed immutable reads; uncached reads and cache failures need separate qualification. The measured repeated-read workload benefits from this design, while mostly cold reads or mutable records require their own availability evidence.

The managed database, Redis, load balancer and broader zone infrastructure remained outside the selected-node shutdown footprint. This boundary determines how far the zonal results can be generalized.

## 3. What the tests required

The workload scheduled 20 business operations per second, with an 80% read / 20% write mix, plus one independent read/write canary per second. A *canary* is a separate client probe that checks business behavior throughout the fault. The harness counted failed logical operations, raw failed attempts and dropped scheduled work separately.

Compute tests required at least 99% business success over the first 300 seconds after the observed effect, with successful-operation p95 latency at most two seconds and no complete canary outage longer than five seconds. The *p95 latency* is the time within which 95% of successful operations completed; failed and dropped work is reported separately. Database and combined tests used a 99.9% full-phase business-availability gate. Recovery had to begin a complete qualifying 60-second window within 180 seconds, followed by 300 stable seconds. These gates measure different properties, so automatic recovery and retained writes can coexist with an availability FAIL.

### App Service outcomes

| Attempt | Recorded outcome | What the evidence supports |
| --- | --- | --- |
| Baseline | PASS: 100% business success; p95 123 ms | The Windows workload qualified before injection |
| Linux application-process deletion | BLOCKED: unsupported deletion wherever process listing worked | The chosen native fault could not qualify Linux process-crash resilience |
| Windows exact-instance process crash | PASS: zero failed business operations; replacement started 12.7 s after acceptance | Surviving workers maintained business service during a discrete process restart |
| Windows processes on both workers in one zone | PASS: zero failed business operations; replacements started in 11-13 s | Correlated application-process loss was tolerated within the selected zone |
| PostgreSQL forced failover | Recovery/durability PASS; full-phase availability FAIL at 97.347%; recovery 36.359 s | Automatic database recovery worked, with a customer-visible availability shortfall |
| Database failover plus process crash | Recovery/durability/observed overlap PASS; full-phase availability FAIL at 97.324%; recovery 34.989 s | The application recovered through independently verified overlapping effects, while missing the availability gate |
| Physical whole-zone outage | BLOCKED | No qualifying physical-zone disaster was injected |

These process tests are useful for worker restart and surviving-capacity behavior. Their effects ended as App Service restarted the processes; sustained loss of the zone's infrastructure was outside their scope. The [App Service report](app-service-results.md) preserves earlier failed setup and qualification attempts.

### AKS outcomes and version boundaries

| Attempt or version | Recorded outcome | What the evidence supports |
| --- | --- | --- |
| Original architecture: node shutdown | FAIL: first-five-minute business success 98.95%; recovery 39.181 s | Automatic recovery and retention worked, while short-window availability missed 99% |
| Original architecture: selected-zone compute shutdown | FAIL: first-five-minute 97.85%; full-phase 98.9629630%; recovery 64.320 s | Sustained owned-compute loss was proven, with insufficient business availability |
| Original architecture: PostgreSQL / combined faults | Full-phase availability FAIL at 98.0093514% / 97.4445628%; recovery 28.551 s / 28.855 s | Recovery and retention passed; original combined-effect overlap was independently proven |
| First cache/HTTP/1.1 repair: node / selected-zone compute | Both PASS: first-five-minute 100%; full-phase 99.962965% / 99.949076% | The repaired version tolerated the specified sustained compute faults; eight / eleven full-phase business failures remain recorded |
| First repair: PostgreSQL failover | FAIL: full-phase 99.379658%; 49 failures and 85 business drops | Local cache misses on cold workers and admission limitations exposed a residual read path |
| Shared-cache repair before full load preallocation: PostgreSQL failover | FAIL: 99.763900%; zero failed logical business operations, 51 business drops | The failed-read pattern disappeared, while scheduled-load delivery still missed its gate |
| Final baseline, shared cache and preallocated load | PASS: 12,001 business successes, zero failures/drops; p95 11 ms | The final version qualified at baseline |
| Final PostgreSQL failover | Business phase PASS: 21,600 successes, zero business failures/drops; overall INCONCLUSIVE | The topology observer stopped after 20 samples; 22 canary schedules were dropped despite all 1,058 completed canaries succeeding |
| Final-version node / zone-compute / combined reruns | Incomplete: node and zone were not rerun on this version; repaired combined was not executed | Earlier-version PASS results cannot qualify the complete final suite |
| Physical whole-zone outage | BLOCKED throughout | Selected owned-node shutdown supplied a narrower compute-failure experiment |

The final database run also recorded 413 failed business attempts that later reconciled to SQL-confirmed logical success. Its business result is useful evidence of the cache, retry and reconciliation behavior. The missing observation horizon and canary drops remain explicit, so it supplies no overall HA PASS. The [AKS results register](aks-results.md#final-bounded-close-summary----7-november-2026) retains every original and repair result.

## 4. Where Chaos Studio was useful, and where coverage stopped

Native Actions supplied repeatable, scoped process crashes, sustained AKS compute shutdown and PostgreSQL forced failover. Independent caller auditing, power-state samples, database-role checks and client measurements connected each accepted Action to an actual effect. This exposed availability shortfalls that healthy nodes, successful provisioning or a completed Action alone would have hidden.

Coverage was weaker where the fault mechanism could not represent the desired disaster. Linux process deletion was unsupported. Windows zone-selected crashes restarted processes on otherwise available infrastructure. AKS zone-compute shutdown left regional managed dependencies running. PostgreSQL forced failover exercised promotion and reconnection with an available HA partner. Each case informs the mechanism it actually exercised.

DR therefore needs a separate recovery design and exercise: a recovery location or restore target, data-recovery mechanism, client traffic redirection, and measured *recovery time objective (RTO)* and *recovery point objective (RPO)*. RTO bounds the time to restore service; RPO bounds acceptable data loss. The lab's 180-second local recovery target and acknowledged-write checks apply to its injected faults. Regional recovery and recovery of all data after a disaster remain unmeasured.

## 5. Durability, comparison and operating limits

App Service reconciliation retained 92,616 of 92,616 acknowledged measurement writes across 31 Linux/Windows runs. Final AKS direct PostgreSQL reconciliation retained 78,142 of 78,142 acknowledged measurement writes across 21 runs, plus 23 of 23 private-verification journal acknowledgements. These are separate histories. The final AKS check bypassed both caches and compared stored checksum values with client acknowledgements; payload JSON was not independently rehashed.

The platform comparison also changed region, runtime, ingress, fault mechanism and later cache behavior. The results describe those particular tested configurations and workloads; they cannot rank the platforms universally or isolate a single change as the cause of improvement.

Private workload paths qualified, with a separate AKS governance exception: Defender created an external Log Analytics workspace whose public ingestion/query remained enabled. The external-scope safeguard stayed FAIL. App Service group deletion was verified on 6 November; AKS teardown later became operator-managed and completion was not verified. Exact identifiers and raw evidence remain excluded from publication.

## 6. Decision and next evidence

Use the Windows process-crash and repaired AKS compute results as qualified evidence for their recorded versions and bounded fault scopes. Preserve database availability failures, the final observer gap and the incomplete same-version suite as open acceptance items.

The next HA exercise should qualify one supported, pinned version across baseline, exact node, selected-zone compute, database and combined faults, with complete independent observations and all dropped work retained. Cache outage and uncached-read cases should be added because the final design introduced that dependency. A separate DR exercise should then measure service and data recovery through the intended regional-failover or restore path. HA component results and DR readiness each need evidence matching their recovery scope.

## Evidence and next reading

1. [Reading guide](lab-guide.md): ordered route, document roles and historical material.
2. [App Service execution results](app-service-results.md): measured Windows outcomes and earlier Linux attempts.
3. [AKS final close and complete result history](aks-results.md): version-specific verdicts and reconciliation.
4. [Experiment limits](experiment-limits.md): acceptance gates, fault footprints and interpretation.
5. [AKS architecture and contracts](aks-lab.md): topology, caching, load and targeting details.
