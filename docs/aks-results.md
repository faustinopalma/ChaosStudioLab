# Private AKS comparison results register

[Lab guide](lab-guide.md) · [AKS design and tests](aks-lab.md) · [Experiment limits](experiment-limits.md) · [Historical App Service results](app-service-results.md)

Final evidence date for the original architecture: 7 November 2026, read-only verification completed at **14:29:18.8910812 UTC**. **The original requested suite has no complete PASS:** baselines passed, every measured fault case failed a required gate, and HA-AZ-001 remains BLOCKED. Combined effect/overlap/recovery/stability/retention/placement passed while full-phase availability failed. Final private qualification passed; all **37,659 of 37,659** acknowledged writes/ten runs were retained. Four owned groups are left active, with strict external scope delta FAIL.

Separately, external scope delta remains **FAIL**: original 24 unrelated IDs/complete returned metadata are unchanged, but one extra default Log Analytics workspace exists outside owned groups. Creation by the subscription's Defender for Containers managed identity is independently proven. Public ingestion/query remain Enabled; no all-security-telemetry-private verdict is established.

## Follow-up architecture repair and conditional teardown

The operator's later 7 November instruction authorizes architectural corrections, unchanged native-suite reruns and teardown of this experiment's owned resources **after successful tests**. This supersedes the original leave-running instruction. Original FAIL results and the genuine whole-zone HA-AZ BLOCKED boundary remain preserved.

The fresh in-place repair run uses the existing four owned groups and one private runner. Read-only diagnosis confirms healthy private AKS/PostgreSQL and six distinct application workers before publication. The proposed [immutable-read cache and ingress protocol repair](aks-lab.md#immutable-read-cache-and-ingress-protocol-repair) retains SQL commit/checksum guarantees and original load/acceptance criteria.

Initial local validation passes: 15 API tests against the actual .NET 10 target, load/drop/token-redaction fixtures, exact native target/zone contracts and private AKS Bicep/infrastructure fixtures. These checks establish source prerequisites. Live rollout, fresh baseline and all four native fault reruns require their own evidence; the original suite has no complete PASS.

Teardown is conditional on qualified native tests. The external Defender-created workspace remains outside the manifest and the pre-existing default group remains protected. Publish any residual retained data/resource exception independently; successful workload tests alone cannot turn its scope/privacy finding into PASS.

## Live qualification and provisioning history

| Item | Available fact | Qualification boundary |
| --- | --- | --- |
| Authorization/scope | Autonomous implementation, deployment, repairs and tests authorized; scope and identities deployed; retain groups until operator stop/delete order | Current inventory/health recheck before each measured case |
| Original ARM validation | Passed; 42 Creates and five owned-identity Ignores | Counts describe the validated change plan, rather than fault effects or measurement outcomes |
| Region/VM eligibility | Sweden Central `Standard_D4ds_v5` qualified in zones 1/2/3; initial Italy North VM candidate restricted | Allocation/placement recheck before each case |
| Physical-zone mapping | Logical 1/2/3 map to `swedencentral-az1`/`swedencentral-az2`/`swedencentral-az3` | Case-specific target/effect correlation |
| PostgreSQL | Private smoke and HA qualified; final primary 1/standby 2 Healthy | Role swap/recovery/stability PASS; database/combined full-phase availability FAIL |
| Kubernetes | Live private AKS 1.35.9 on Azure Linux 3.0; baseline/final qualification PASS | Fault acceptance remains independently FAIL |
| AKS shape | Final nine Ready Linux nodes/six distinct Ready user workers/three physical zones | Earlier original node five-worker restoration FAIL is preserved |
| Native node contract | Live Action has `GracefulShutdown` and `Zones`, without instance IDs; shutdown definitions PT7M | Accepted targets and at least 300 s observed continuous power-off, shutdown state and restoration semantics |
| Selected-zone target configuration | Exactly system/z1a/z1b VMSS with zone 1 selected; other four pools omitted | Three-node 304.0433 s effect PASS; first-window/full-phase availability FAIL |
| Native non-fault qualification | Workspace discovery PASS; exact-node, selected-zone and database validation PASS | Actual Action execution, independent effects and caller/audit correlation |
| Node-group authorization | Runner Reader; Chaos Virtual Machine Contributor and Reader | Effective scoped grants, independent reads and actual fault-caller evidence |
| Private paths | Private API/PG/ACR/KV DNS inside approved subnets; SSH and private API verified through Bastion; private application HTTPS 200 | Case-specific connectivity and observation continuity |
| Runtime/publication | Six live .NET 10 pods using pinned private ACR image digest; authentication, idempotence and checksum smoke verified | Measured revision continuity and complete-history retention |
| Application logs | Private Kubernetes API/runner evidence; templates omit AMPLS/application Log Analytics | Complete attributable private business log collection/cadence |
| Managed security telemetry | Enabled Defender monitoring/gating references external default Log Analytics; managed creation independently proven; public ingestion/query Enabled | Operator review; no all-telemetry-private verdict |
| External scope | Original 24 unrelated IDs/complete returned metadata unchanged; one governance-managed workspace makes inventory 25 | Delta guard FAIL; workspace/group untouched and outside lab manifest |
| Workload probe | Process-live readiness retains endpoints during dependency outage; `/health/ready` remains qualification gate | Actual probe configuration, baseline/restored-health checks and independent business results |
| Independent observations | Remote runner observer and node-topology monitor; raw lab measurement evidence retained under ignored `.local\` | Complete attributable client/topology samples, power states and observation cadence |

Successful qualification and non-fault validation establish prerequisites. Original node availability/placement failed; corrected twelve-minute stability failed; eighteen-minute exact first-five-minute availability failed. Workload private-path qualification does not remove the security telemetry exception or scope delta FAIL.

## External resource and managed security telemetry finding

One default regional Log Analytics workspace was created at **10:56:57 UTC** in a pre-existing group outside the **four owned lab groups**. The original 24 unrelated resource IDs and complete returned metadata remained unchanged; protected inventory increased to 25 and the hard delta safeguard reports **FAIL**.

Actual AKS Defender `securityMonitoring.enabled=true` and `securityGating.enabled=true` reference that workspace. `addonProfiles` and `azureMonitorProfile` are null. Workspace public ingestion and query are Enabled. Planned omission of application Log Analytics/AMPLS does not describe all live security telemetry.

Correlated Started/Accepted/Succeeded workspace Activity Log writes independently authenticate the subscription's Defender for Containers managed identity. The actual AKS Defender profile references the created workspace, proving governance-managed creation. Exact IDs/claims are privately retained.

No PC command explicitly created/modified/deleted that workspace/group or changed governance. The group remains untouched for operator review, and proven managed attribution does not make the workspace lab manifest-owned. No automatic deletion, governance disabling or exemption renewal is performed; strict scope delta remains FAIL.

Private application/API/PG/ACR/KV paths and raw business measurement logs remain qualified/private. Publish the telemetry and scope exception separately from service results, with exact IDs retained only in ignored evidence.

## Provisioning and troubleshooting findings

| Finding | Narrow repair or verified outcome | Attribution and limit |
| --- | --- | --- |
| Main deployment DNS A-record race | Repaired the sole failed DNS record narrowly; successful cluster and database were not redeployed | Provisioning repair; original deployment outcome and repair remain distinct |
| Initial bootstrap HTTPS check | Curl raced internal-load-balancer availability after pods became Ready and timed out at 134 s; the existing image was privately requalified without restarting or rebuilding | Provisioning/readiness timing; 134 s is the failed check duration, rather than measured fault recovery |
| Singleton DNS verifier | Array-handling bug fixed and proven against live private DNS | Qualification-tool repair; private API/PG/ACR/KV resolution subsequently verified |
| PC local tunnel port | Windows rejected local 50222 with `WinError 10013`; local 40222 worked through the same Bastion path, with SSH and private API verified | Local management connectivity troubleshooting; no public application path was introduced |
| Initial exact-node preparation | Singleton VM selection unrolled to a scalar and `.Count` failed; repaired entrypoint fixture tests one-VM and three-VM arrays | Failed before load/injection; separate from actual fault measurement |
| Attributable diagnostic observers | Stopped only two verified attributable observer PIDs | Local runner diagnostic-process cleanup; no Azure resource stop or deletion |

Preserve the original deployment/bootstrap findings in private evidence. The completed qualification used the existing cluster, database and digest-pinned image. Pod readiness preceded ILB reachability in the failed bootstrap check; qualified HTTPS and `/health/ready` are therefore independent gates.

Provisioning and troubleshooting totals remain unsummed. Keep these durations separate from warmup, baseline, fault load and reconciliation; no measurement total is inferred from this history.

## BASE-001 measured result

BASE-001 completed **PASS** at about 11:03 UTC. Five-minute warmup also passed. All acknowledged writes were retained with matching checksums; the baseline-only write count was not supplied. Later complete-history totals are recorded below.

| Ten-minute baseline measurement | Result |
| --- | ---: |
| Successful business operations | 12,001 |
| Failed business operations | 0 |
| Dropped business/canary operations | 0 / 0 |
| Successful/failed canaries | 601 / 0 |
| Business success | 100% |
| Successful-operation p95 | 11 ms |
| Measured baseline duration, including finalization | 609.234 s |

The load was configured for ten minutes; finalization accounts for the reported duration exceeding 600 seconds. Raw case/run identifiers remain in private evidence.

## Original HA-NODE-001 measured result

The actual retry began at **11:14:14 UTC**; native acceptance occurred at **11:15:04 UTC**. Exact VM power-off was independently sustained for **at least 300.292 s**, while surviving pods served traffic in all three logical zones. Native execution and independent target-operation caller/object-claim auditing passed, verifying the declared Workspace user-assigned managed identity despite incorrect reported-principal metadata.

| Twelve-minute full-phase measurement | Result |
| --- | ---: |
| Successful logical business operations | 14,307 |
| Failed logical business operations | 93 |
| Logical business success | 99.3541667% |
| Configured full-phase success threshold | 99%: PASS |
| Raw failed attempts, including retry attempts | 348 |
| Dropped business/canary operations | 0 / 0 |
| Successful/failed canary ticks | 721 / 0 |
| Successful-operation p95 | 11 ms |

| Required first 300 seconds after observed power-off | Result |
| --- | ---: |
| Logical business operations | 6,000 |
| Failed logical business operations | 75 |
| Business success | 98.75%: FAIL against 99% |
| Successful-operation p95 | 11 ms |
| Complete canary unavailability | 0 |

The whole-phase aggregate PASS cannot replace the required first-five-minute gate. **The original case remains FAIL.** All-history acknowledged-write/checksum retention completed successfully; no numerical history total was supplied at this earlier checkpoint. Later NODE18/zone totals are recorded below.

Offline independent re-evaluation preserved availability FAIL while separately qualifying these results:

| Independent gate or timing | Result |
| --- | --- |
| Recovery to beginning of qualifying 60-second window | **PASS**, 47.434 s |
| Continuous 300-second stable window | **PASS** |
| All-history retention reconciliation elapsed | 97.7048 s |
| Workload measurement elapsed | 731.188 s |
| Whole case elapsed | 1,026.2697 s |

The whole-case duration includes work beyond the configured load phase; do not label it fault duration or infer a complete timing breakdown from these totals.

Nine Ready nodes and six Ready pods recovered automatically without manual restart during measurement. However, two pods occupied z1b and none occupied the returned z1a, leaving only five distinct workers. Automatic six-worker baseline restoration therefore failed. The native measurement completed before any configuration correction.

The principal-metadata discrepancy remains recorded with its successful independent audit. Fault effect, availability, retention, service recovery and restored placement retain separate verdicts.

The earlier singleton-selection failure occurred before load or injection and has separate troubleshooting attribution. It is not a failed native fault execution.

## Live post-measurement correction and qualification

Before rollout, Bicep/private invariants, native contracts and effect fixtures passed. Fixtures explicitly preserve availability FAIL alongside recovery/stability PASS. The correction was applied outside fault measurement and **qualified at 11:46:14 UTC**; apply/rollout/qualification took **67.7708 s**:

- Live hard hostname anti-affinity qualified one application pod per user node. Node/zone faults should leave five/four serving pods, with missing replicas Pending until node capacity returns. Automatic fault restoration still needs corrected-run evidence.
- Live private Service Local routing qualified its actual Azure ILB HTTP `/healthz` probe on the allocated health-check node port: interval 5 s, `numberOfProbes=2`, `probeThreshold=2`, state Succeeded. Failed-node withdrawal still requires measured fault evidence.

All six distinct workers/three observed zones and every pod's health/checksum traffic qualified. Private IP, TLS, immutable image/business revision, six replicas, six user pools and all thresholds are unchanged. Preserve the original failure/learning and distinguish post-measurement setup from fault recovery.

Owned Kubernetes server dry-run/diff preceded apply, limiting changes to Deployment anti-affinity, Service Local/probe settings and server-allocated `healthCheckNodePort`; namespace, service account and PDB were unchanged. Actual Service/anti-affinity guards qualify the resulting configuration. Source checkpoint: `f8614d1`.

## Fresh corrected BASE-001 measured result

Fresh corrected **BASE-001 PASS** includes warmup, ten-minute baseline, all acknowledged-write/checksum retention and final six-distinct-worker/three-zone requalification.

| Measurement | Five-minute warmup | Ten-minute baseline |
| --- | ---: | ---: |
| Successful business operations | 6,001 | 12,001 |
| Failed business operations | 0 | 0 |
| Dropped business/canary operations | 0 / 0 | 0 / 0 |
| Successful/failed canaries | 301 / 0 | 601 / 0 |
| Business success | 100% | 100% |
| Successful-operation p95 | 10 ms | 11 ms |
| Measured duration including finalization | 305.344 s | 609.336 s |

Baseline measurement ran **11:55:47.2948832–12:05:56.6310198 UTC**. The whole case ran **11:48:17.9038625–12:08:32.3068181 UTC**, elapsed **1,214.403 s**; retention reconciliation took **248.484 s**. All acknowledgements/checksums were retained; the baseline-only write count was not supplied. Later complete-history totals are recorded below. Do not equate whole-case time with configured load or fault duration.

## Corrected twelve-minute HA-NODE-001 measured result

Corrected retry load began at **12:13:10 UTC** and native acceptance occurred at **12:13:59 UTC**. Native execution/independent identity audit passed. Exact-node power-off was sustained for **at least 303.8277 s**, survivors served in three zones, and final nine Ready nodes/six Ready pods/six distinct workers/three zones restored automatically.

| Corrected twelve-minute full phase | Result |
| --- | ---: |
| Successful/failed logical business operations | 14,338 / 63 |
| Logical success | 99.5625304% |
| Raw failed attempts | 402 |
| Business/canary drops | 0 / 0 |
| Successful/failed canaries | 718 / 3 |
| Successful-operation p95 | 11 ms |
| Workload measurement elapsed | 731.371 s |
| Retention reconciliation elapsed | 107.4279 s |
| Whole case elapsed | 1,052.8950 s |

| Independent corrected-node gate | Result |
| --- | --- |
| First 300 s business operations/failures | 6,000 / 32 |
| First 300 s business success | **PASS**, 99.4666667% |
| First 300 s successful-operation p95 | **PASS**, 11 ms |
| Longest complete canary unavailability | **PASS**, 1 s |
| Sustained power-off | **PASS**, at least 303.8277 s |
| Recovery to qualifying 60-second window | **PASS**, 0.732 s |
| Continuous 300-second stable window | **FAIL**, none of 362 complete candidate windows qualified |
| Automatic final placement | **PASS**, nine Ready nodes/six Ready pods/six distinct workers/three zones |
| Acknowledged-write/checksum retention | **PASS** |

Initial evaluation was **INCONCLUSIVE** because an expected unscheduled Pending replacement had no `nodeName`. The evaluator now skips only unscheduled Pending pods and rejects unscheduled non-Pending pods; fixtures passed. The saved original analysis remains preserved. Re-evaluation used **unchanged raw data without resubmitting a fault**, and **the corrected case is FAIL** because stability failed.

Late failures continued through 12:22 and measurement ended at 12:25:24, leaving fewer than five stable minutes. Stable FAIL now propagates FAIL rather than INCONCLUSIVE. Short recovery, successful placement and full-phase success do not override that gate.

## Eighteen-minute HA-NODE-001 measured result

All subsequent fault load phases use **18 minutes** with **20-minute bounded observers**, allowing a complete 300-second stable interval after seven-minute shutdown/restoration. First-five-minute thresholds, load rate, VU caps and native PT7M duration are unchanged. No architecture/image change or baseline reset is made.

The eighteen-minute case began load at **12:41:48 UTC**, with native acceptance at **12:42:37 UTC**. Native/audit passed, and all selected VMs were independently off for **306.1511 s**. Automatic final six-distinct-worker/three-zone placement and all-history acknowledged-write/checksum retention passed.

| Exact first-five-minute gate | Result |
| --- | --- |
| Expected business operations/canary samples | 6,000 / 300 |
| Dropped business/canary operations | 0 / 0 |
| Failed business operations | 63 |
| Business success | **FAIL**, 98.95% against 99% |
| Successful-operation p95 | **PASS**, 11 ms |
| Longest complete canary unavailability | **PASS**, 1 s |
| Sustained selected-VM outage | **PASS**, 306.1511 s |

The permitted maximum is **60 failures among 6,000 operations**. The recorded 63 failures constitute a measured FAIL; **the overall case remains FAIL**.

| Recovery and stable gate | Result |
| --- | --- |
| Recovery to qualifying 60-second window | **PASS**, 39.181 s |
| Continuous 300-second stable window | **PASS**, 12:50:35–12:55:35 UTC |
| Stable business success | 5,994 / 6,000, exactly 99.9% |
| Stable canary success | 300 / 300 |
| Stable successful-operation p95 | 11 ms |

| Eighteen-minute full phase | Result |
| --- | ---: |
| Successful/failed logical business operations | 21,504 / 97 |
| Logical success | **PASS** against recorded phase gate, 99.5509467% |
| Raw failed attempts | 458 |
| Successful/failed canaries | 1,077 / 3 |
| Business/canary drops | 0 / 0 |
| Successful-operation p95 | 11 ms |
| Measured duration including finalization | 1,096.296 s |

Measurement ran **12:41:51.4108345–13:00:07.7066202 UTC**. Longer observation supplied a qualifying stable window only; earlier stable FAIL and the current first-window FAIL remain preserved. Do not recast the overall case as PASS or repeatedly rerun until a favorable outcome. The root of recurrent late eight-second transport failures remains unproven.

The whole NODE18 case ran **12:40:17.9547357–13:05:13.7684786 UTC**, elapsed **1,495.8141 s**; reconciliation took **118.0928 s**, verifying **21,594 acknowledged writes across seven AKS history runs** with zero loss/checksum failures.

Raw transport diagnosis recorded **458 business failed attempts plus 51 canary failed attempts**, all status 0 and approximately eight seconds long, recurring **12:42–12:52**. Keep attempt/tick/logical-operation denominators separate. These symptoms leave root cause unproven.

Evaluator/horizon/metadata/SVG checkpoint: `7e7477d`; application source/image revision remains `21ca987`. Raw case/run IDs remain private.

## HA-ZONE-COMPUTE-001 measured result

Selected-zone native shutdown accepted at **13:08:07 UTC**. Native/authenticated audit passed. Exactly three selected VMs, system-zone-1/z1a/z1b, were off for **304.0433 s**, while six others remained running and traffic came from surviving logical zones 2/3. Automatic final six-distinct-worker/three-zone placement passed.

| Exact first-five-minute gate | Result |
| --- | --- |
| Business operations/failures | 6,000 / 129 |
| Business success | **FAIL**, 97.85% against 99% |
| Expected canary samples | 300 |
| Business/canary drops | 0 / 0 |
| Successful-operation p95 | **PASS**, 11 ms |
| Longest complete canary unavailability | **PASS**, 1 s |
| Selected-VM off duration | **PASS**, 304.0433 s |

| Recovery and stable gate | Result |
| --- | --- |
| Recovery to qualifying 60-second window | **PASS**, 64.320 s |
| Continuous 300-second stable window | **PASS**, 13:17:41–13:22:41 UTC |
| Stable business success | 5,994 / 6,000, 99.9% |
| Stable canary success | 300 / 300 |
| Stable successful-operation p95 | 11 ms |

| Eighteen-minute full phase | Result |
| --- | ---: |
| Successful/failed logical business operations | 21,376 / 224 |
| Logical business success | **FAIL**, 98.9629630% against 99% |
| Raw failed business attempts | 774 |
| Successful/failed canaries | 1,078 / 3 |
| Business/canary drops | 0 / 0 |
| Successful-operation p95 | 11 ms |
| Measured duration including finalization | 1,096.337 s |

Measurement ran **13:07:20.8248617–13:25:37.1623441 UTC**. The whole case ran **13:05:52.572568–13:31:07.6184184 UTC**, elapsed **1,515.0483 s**; retention reconciliation took **138.2711 s**. It verified **26,966 acknowledged writes across eight AKS history runs**, with zero loss/checksum failures.

**Overall FAIL** preserves both first-five-minute and full-phase availability failures. Recovery, stability, placement and complete-history retention PASS remain separate. This is selected-zone lab compute evidence; HA-AZ-001 remains BLOCKED.

## HA-DB-001 reconciled measured result

Database native failover accepted at **13:33:34 UTC** executed successfully and authenticated the exact declared Workspace identity. Initial pipeline **FAIL** resulted from the topology observer exiting on one **ten-second ARM GET HttpClient timeout**. Independent dependency/health observation and load completed; original verdict and interrupted topology trace remain preserved.

In-place reconciliation retrieved **unchanged raw load/health/topology data** and verified complete-history retention without resubmitting a fault. Reconciled effect/recovery/stability/role swap passed using the complete independent dependency probe and actual role inventory. No complete topology-observer result is claimed.

| Recovery and stable gate | Result |
| --- | --- |
| Recovery to complete sixty-second window | **PASS**, 28.551 s |
| Recovery window start | 13:34:19 UTC |
| Recovery business/canary successes | 1,200 / 1,200; 60 / 60 |
| Recovery successful-operation p95 | 15 ms |
| Stable window | **PASS**, 13:34:19–13:39:19 UTC |
| Stable business/canary successes | 6,000 / 6,000; 300 / 300 |
| Stable successful-operation p95 | 15 ms |
| Native effect/actual role swap | **PASS** |

| Eighteen-minute full phase | Result |
| --- | ---: |
| Successful logical business operations | 21,171 |
| Failed logical business operations | 317 |
| Dropped business operations | **113** |
| Business success including dropped scheduled work | **FAIL**, 98.0093514% against 99.9% |
| Raw failed business attempts | 669 |
| Successful/failed canaries | 1,051 / 10 |
| Dropped canaries | **20** |
| Successful-operation p95 | 13 ms |
| Measured duration including finalization | 1,096.004 s |

The business denominator is success + logical failure + dropped scheduled work; omitted drops would misstate availability. Measurement ran **13:32:48.4067226–13:51:04.4103113 UTC**. Original case elapsed was **1,277.1220 s**; unchanged-data reconciliation completed at **13:59:25 UTC**.

All-history retention verified **32,330 acknowledged writes across nine AKS history runs**, with zero loss/checksum mismatch. **Reconciled overall FAIL** preserves failed full-phase availability despite native/effect/recovery/stable/role-swap/retention PASS, alongside the initial pipeline observer failure.

## Observer handling repair

Repair checkpoint **`3bf7d66`** diagnoses known transient ARM timeout/429/5xx, discards the entire incomplete topology sample and continues the next bounded observation. The **30-second maximum gap remains unchanged**, and unauthorized errors are fatal. Future orchestration retrieves load/retention before reporting observer failure; actual catch-handling fixtures passed. This supplies no missing samples to the original trace.

## HA-COMBINED-001 final measured result

Combined load began **14:01:44 UTC**. Database accepted at **14:02:34.5311 UTC** and selected-zone compute accepted at **14:02:55.9887 UTC**, after an independent bad dependency observation. Both native results were Succeeded and both authenticated identity audits passed. Both independent observers exited **0**.

The three selected VMs were off for **at least 300.1613 s**. Independent overlap evidence is:

| Observation | UTC timestamp |
| --- | --- |
| First database disruption | 14:02:50.1449589 |
| Bracketing database 503 request before power-off | 14:03:02.2493908 |
| Actual observed power-off | 14:03:09.8203411 |
| Bracketing database 503 request after power-off | 14:03:15.5460861 |
| Response to the latter request | 14:03:16.5696703 |

There was **no intervening healthy dependency observation**. Actual effect/overlap passed independently of native submission timing.

| Recovery and stable gate | Result |
| --- | --- |
| Recovery from first database disruption | **PASS**, 28.855 s |
| Complete sixty-second recovery window start | 14:03:19 UTC |
| Recovery business success | 1,193 / 1,200, 99.4167% |
| Recovery canary success | 60 / 60 |
| Recovery successful-operation p95 | 15 ms |
| Complete 300-second stable window | **PASS**, 14:12:12–14:17:12 UTC |
| Stable business success | 5,994 / 6,000, 99.9% |
| Stable canary success | 300 / 300 |
| Stable successful-operation p95 | 11 ms |
| Automatic final placement | **PASS** |

| Eighteen-minute full phase | Result |
| --- | ---: |
| Successful logical business operations | 21,049 |
| Failed logical business operations | 434 |
| Dropped business operations | **118** |
| Business success including dropped scheduled work | **FAIL**, 97.4445628% against 99.9% |
| Raw failed business attempts | 1,212 |
| Successful/failed canaries | 1,047 / 14 |
| Dropped canaries | **20** |
| Successful-operation p95 | 13 ms |
| Measured duration including finalization | 1,096.448 s |

The whole case ran **14:00:01.7834563–14:25:42.447896 UTC**, elapsed **1,540.6647 s**; retention reconciliation took **149.4105 s**. Complete history verified **37,659 of 37,659 acknowledged writes across ten AKS runs**, with zero lost writes/checksum mismatch.

**Overall FAIL** preserves full-phase availability failure. Native/authenticated identity, both observers, effect, overlap, recovery, stability, retention and final placement PASS remain separately visible. Neither recovery nor proven overlap erases the availability miss.

## Test verdicts

| Test | Execution/effect | Service recovery | Full-phase availability | Complete-history retention |
| --- | --- | --- | --- | --- |
| BASE-001 | **PASS**: warmup and ten-minute baseline | No fault; not applicable | **PASS**: 100%, p95 11 ms | **PASS**: all baseline acknowledged writes/checksums retained |
| HA-NODE-001 original | **PASS** sustained shutdown/native audit; overall case **FAIL** at required-window availability and six-worker restoration | **PASS** recovery 47.434 s and 300 s stability; six-worker restoration **FAIL** | Configured 99% phase gate **PASS**, 99.3541667%; first-300-second 99% gate **FAIL**, 98.75% | **PASS**: all-history acknowledged writes/checksums retained |
| BASE-001 corrected | **PASS**: warmup, baseline and final six-worker/three-zone requalification | No fault; not applicable | **PASS**: 100%, baseline p95 11 ms | **PASS**: all acknowledgements/checksums retained |
| HA-NODE-001 corrected, 12 min | **PASS** native/audit/sustained effect; overall **FAIL** stability | Recovery **PASS**, 0.732 s; stable **FAIL**; six-worker restoration **PASS** | Phase 99.5625304%; first-300-second gate **PASS**, 99.4666667%, max complete outage 1 s | **PASS** |
| HA-NODE-001 corrected, 18 min | **PASS** native/audit/306.1511 s effect; overall **FAIL** first-five-minute availability | **PASS**, 39.181 s recovery/300 s stable/six-worker restoration | Phase **PASS**, 99.5509467%; first-five-minute **FAIL**, 98.95% | **PASS**, all-history |
| HA-ZONE-COMPUTE-001 | **PASS** native/audit/three-VM 304.0433 s effect; overall **FAIL** availability | **PASS**, recovery 64.320 s/stable 300 s/six-worker restoration | **FAIL** full phase 98.9629630% and first-five-minute 97.85% | **PASS**, 26,966 writes/eight history runs |
| HA-DB-001 | Native/audit/effect/role swap **PASS**; initial interrupted-observer pipeline **FAIL**; reconciled overall **FAIL** availability | **PASS**, recovery 28.551 s/complete 60 s window/stable 300 s | **FAIL**, 98.0093514%; 113 business/20 canary drops | **PASS**, 32,330 writes/nine history runs |
| HA-COMBINED-001 | Native/audit/both observers/effect/overlap **PASS**; overall **FAIL** full-phase availability | **PASS**, recovery 28.855 s/stable 300 s/final placement | **FAIL**, 97.4445628%; 118 business/20 canary drops | **PASS**, 37,659/37,659 writes/ten runs |
| HA-AZ-001 | **BLOCKED**, no fault; final guard exit **1**, no Azure changes | Unmeasured | Unmeasured | Unmeasured |

HA-AZ-001 has no injected physical full-zone result. Its final guard explicitly exits 1 and fixtures pass; it makes no Azure changes. Baselines are PASS; all three node cases, selected-zone, reconciled DB and combined cases are FAIL at required gates. Complete-suite PASS is withheld.

| Separate environmental gate | Verdict |
| --- | --- |
| Original 24 unrelated IDs/complete returned metadata | **PASS**, unchanged |
| Total protected inventory | **FAIL**, 25 versus original 24; one extra external workspace |
| Creator attribution for extra workspace | **PASS**, correlated Activity Log writes authenticate subscription Defender for Containers managed identity; AKS profile references created workspace |
| All-security-telemetry privacy | Unqualified; referenced workspace public ingestion/query Enabled |

## Measurement register

| Measurement | AKS value |
| --- | --- |
| Baseline business success and successful-operation p95 | 100%; 11 ms |
| Per-phase scheduled successes, failures and drops | Original node 14,307 / 93 / 0; corrected node 14,338 / 63 / 0 |
| Independent canary successes, failures, drops and maximum complete outage gap | Original node 721 / 0 / 0, zero complete outage; corrected node 718 / 3 / 0, max complete outage 1 s |
| Exact-node actual effect, continuous off duration and restoration | Original at least 300.292 s/five final workers; corrected at least 303.8277 s/six final workers |
| Selected-zone expected/observed target counts and continuous off duration | Three expected/observed VMs off 304.0433 s; six others running, surviving traffic zones 2/3 |
| Surviving pods, rescheduling and AKS restart/replacement events | Original final z1b two pods/z1a none; corrected-node automatic six-worker/three-zone restoration PASS |
| Original node recovery/stability | PASS: recovery 47.434 s into qualifying 60 s window; stable 300 s PASS |
| Corrected twelve-minute node recovery/stability | Recovery PASS, 0.732 s; stable FAIL, zero of 362 candidate windows qualified |
| Eighteen-minute node gates | Effect 306.1511 s PASS; first-five-minute 98.95% FAIL; recovery 39.181 s/stable 300 s/placement/retention PASS |
| Selected-zone gates | Effect 304.0433 s/recovery 64.320 s/stable/placement/retention PASS; first-five-minute 97.85% and full phase 98.9629630% FAIL |
| PostgreSQL effect/recovery/stability | Native/role swap PASS; recovery 28.551 s, window start 13:34:19; stable 13:34:19–13:39:19 PASS from complete dependency probe |
| Database topology observer | Interrupted on ten-second ARM GET timeout; original trace/pipeline FAIL preserved; no historical sample completion claimed |
| Combined independently observed overlap and recovery | Actual power-off bracketed by database 503 observations; recovery 28.855 s/stable 300 s PASS |
| Complete-history acknowledged-write/checksum totals | NODE18 21,594/seven; zone 26,966/eight; DB 32,330/nine; final combined 37,659/ten, all retained with zero loss/checksum mismatch |
| Original node timing | Workload 731.188 s; reconciliation 97.7048 s; whole case 1,026.2697 s |
| Corrected twelve-minute node timing | Workload 731.371 s; reconciliation 107.4279 s; whole case 1,052.8950 s |
| Correction/fresh baseline timing | Setup 67.7708 s; baseline case 1,214.403 s/reconciliation 248.484 s |
| Eighteen-minute node timing | Workload 1,096.296 s; reconciliation 118.0928 s; whole case 1,495.8141 s |
| Selected-zone timing | Workload 1,096.337 s; reconciliation 138.2711 s; whole case 1,515.0483 s |
| Database timing | Workload 1,096.004 s; original case 1,277.1220 s; reconciled at 13:59:25 UTC |
| Combined timing | Workload 1,096.448 s; reconciliation 149.4105 s; whole case 1,540.6647 s |

## Final private qualification and inventory

Final private qualification **PASS**:

| Item | Verified final state |
| --- | --- |
| AKS | Running; nine Ready Azure Linux nodes |
| Application | Six Ready distinct user workers across three physical zones |
| API server | Private; public FQDN false |
| PostgreSQL | Ready/Healthy zone-redundant HA; primary 1, standby 2; public access Disabled |
| Acknowledged writes | 37,659 / 37,659 across ten runs, zero loss/checksum mismatch |

Final ownership inventory contains **87 resource/definition/exemption IDs**:

| Owned scope | Count |
| --- | ---: |
| Network | 17 |
| Workload | 42 |
| Operations | 11 |
| AKS-managed nodes | 17 |
| Total | 87 |

These are inventoried IDs including definitions/exemptions, not a top-level service-resource count. All **four owned groups are left active**. Original 24 unrelated IDs/complete returned metadata are unchanged plus one external Defender-created workspace. Strict scope delta remains **FAIL** and the public managed telemetry exception remains disclosed. No external cleanup or governance changes were made.

All Azure lab resources remain running/active; only the temporary PC Bastion tunnel helper was stopped. Ignored `.local\<run>\OPERATOR-RESULTS.md` contains exact four-group names/87 IDs, private-access restart instructions and manual deletion steps. Manifest/handoff persist final FAIL, health PASS and all 37,659 retained writes. Source guard/research checkpoint `fae2d0f` passed fixtures and verified the explicit HA-AZ-001 exit-1 guard.

Final read-only inventory verification ran **14:27:52.2912096–14:29:18.8910812 UTC**, elapsed **86.601 s**. Final workload health does not override fault FAILs, physical-zone BLOCKED or scope delta FAIL.

## Elapsed time and attribution

| Category | Recorded duration | Accounting boundary |
| --- | --- | --- |
| Manifest creation → final verified inventory | **18,336.744344 s**, 5 h 05 min 36.744 s | 09:23:42.1467372–14:29:18.8910812 UTC; wall-clock envelope |
| Ten unique measured k6 runs | **7,677.297 s**, 2 h 07 min 57.297 s | Active recorded intervals, including setup/tail; no duplicate reconciliation runs |
| Recorded case-retention subtotal | **859.3913 s**, 14 min 19.391 s | **Incomplete**: excludes unrecorded initial-baseline retention and manual DB reconciliation |
| Known configuration apply/rollout/qualification repair | **67.7708 s** | Post-original-measurement setup correction |
| Final read-only inventory verification | **86.601 s** | Final state/inventory check, not fault measurement |

Retain provider provisioning timings separately:

| Provider stage | Duration | Outcome/overlap |
| --- | --- | --- |
| Root infrastructure deployment | 14 min 20.001 s | **FAIL** on the sole DNS race; successful cluster/DB retained |
| Narrow in-place DNS repair | 2.914 s | Repaired the failed record without redeploying successful cluster/DB |
| Contained workload deployment | 12 min 55.524 s | Parallel child within root interval |
| Contained operations deployment | 9 min 29.713 s | Parallel child within root interval |
| Contained network deployment | 38.243 s | Parallel child within root interval |
| Native definitions | 51.873 s | Separately recorded stage |
| Access | 5.588 s | Separately recorded stage |
| Node access | 38.412 s | Separately recorded stage |
| Identities | 8.022 s | Separately recorded stage |
| Exemption | 3.314 s | Separately recorded stage; no external governance renewal |

**Do not sum parallel children with each other or with the root deployment.** Case envelopes, k6 intervals, retention and verification also have different boundaries; adding them can double-count work.

Research, authorization, diagnosis, unrecorded manual DB reconciliation and operator gaps are **not fully timed**. The remaining wall-clock envelope has an honest unclassified residual; no invented active-work total or complete troubleshooting subtotal is reported.

## Publication requirements for final results

Replace pending values only from final attributable evidence. Preserve failed and blocked attempts, distinguish accepted Actions from independently verified effects, and publish sustained-window failure when AKS remediation weakens the intended fault.

The harness retains independent effects before final-layout checks and aggregates full-phase SLO failure into overall case FAIL, even when native/effect/recovery gates pass. A database/combined availability FAIL requires overall FAIL; component recovery/stability/retention results remain separately visible. Actual harness AST fixtures cover PASS/FAIL/INCONCLUSIVE combinations.

Stable-window FAIL also propagates overall FAIL. Preserve initial INCONCLUSIVE analysis, evaluate only the unchanged attributable evidence for reconciliation, and record any subsequent fault resubmission as a fresh case. Metadata/identifier ownership checks remain order-independent and persist after diagnosis.

Each final case needs actual target counts/zone placement, accepted fault parameters, power-state/NotReady evidence where applicable, surviving service, errors/drops, successful-operation p95, recovery/stable timing, complete-history checksum reconciliation and separate availability/durability verdicts. The combined case additionally needs independent dependency failures overlapping actual compute loss.

The approved compute-only gate covers the first 300 post-effect seconds: at least 99% business success, successful-operation p95 at most two seconds, and no complete outage longer than five seconds. Database/combined recovery allows at most 180 seconds to the beginning of a complete 60-second window at at least 99% business/canary success and successful-operation p95 at most one second. The subsequent stable window requires 300 continuous seconds at 99.9% business success and successful-operation p95 at most one second. Record explicit `/health/ready` qualification separately from Kubernetes process-live readiness and business recovery.

Record whether the node fault stopped or deallocated instances and how service restored them. Verify private Kubernetes API business log collection and independent observer/topology samples. Initial templates omit AMPLS/application Log Analytics, while proven Defender-managed telemetry references the external workspace. Preserve scope delta FAIL and independent attribution evidence. Keep raw identifiers, claims, authentication details and lab measurement evidence under ignored `.local\`.

## Comparison anchor: historical App Service

The measured Windows App Service comparison supplies the following historical reference:

- BASE-001: 100% business success, successful-operation p95 123 ms.
- Exact-instance process replacement: 12.7 s after acceptance; zero failed business operations.
- Selected-zone process replacements: 11–13 s; zero failed business operations.
- PostgreSQL recovery/durability: PASS, 36.359 s recovery; full-phase availability FAIL, 97.347%.
- Combined recovery/durability/overlap: PASS, 34.989 s recovery; full-phase availability FAIL, 97.324%.
- Retention: 92,616 acknowledged measurement writes across 31 Linux/Windows runs, all retained with matching checksums.
- Physical full-zone case: BLOCKED, never injected.

These measurements remain attributed to App Service. The .NET 10 container, private internal load balancer and sustained VMSS node shutdown introduce comparison differences that must accompany any AKS conclusion. Business observation changes from App Service AMPLS to private Kubernetes API logs/runner samples. Separate actual Defender telemetry references an external publicly enabled workspace; no whole-environment telemetry-privacy conclusion follows from private business logs.

## Lifecycle

The earlier App Service dedicated groups were deleted by the operator on 6 November 2026 at 09:43 UTC. Seven unrelated groups and their 24 resources were verified unchanged.

Execution and final verification are complete. All four owned groups remain active until an operator stop/delete order. The proven Defender-managed external workspace/group remains untouched, outside the manifest, with strict scope delta FAIL. No post-suite cleanup was performed.

When explicitly ordered, follow the [manual cleanup order](aks-lab.md#operator-managed-cleanup-order): workload/AKS first, allow service removal of the managed node group and verify absence, then operations and network. **Never delete the pre-existing default regional group or Defender workspace.** Later teardown and retained-object verification require separate evidence.
