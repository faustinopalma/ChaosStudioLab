# Experiment limits and interpretation

[Lab guide](lab-guide.md) · [App Service results](app-service-results.md) · [AKS plan](aks-lab.md) · [AKS results](aks-results.md)

Final evidence dates: App Service 6 November and AKS 7 November 2026. All measured AKS fault cases remain FAIL at required gates; recovery/stability/retention PASS do not override failed availability or placement. Combined overlap is independently proven. Physical full-zone coverage remains BLOCKED; final private qualification passed.

## Separate the verdicts

Each test must publish fault eligibility, accepted targeting, actual effect, sustained duration where required, automatic recovery, full-phase availability and acknowledged-write retention separately.

- **PASS** requires the evidence and thresholds for the named gate.
- **FAIL** records an executed or observed condition that misses its required gate.
- **BLOCKED** records missing eligibility or a safety/evidence prerequisite that prevents qualifying execution.
- **PENDING** records work without a completed qualifying result.
- **INCONCLUSIVE** records insufficient gate evidence; it supplies no overall PASS.

Do not derive a complete-suite PASS from a subset of passed cases. Preserve failed and blocked attempts when a later runtime, topology or package qualifies.

The AKS harness retains independently observed effects before final-layout evaluation and aggregates full-phase SLO failure into overall case FAIL. Native execution, effect and recovery PASS remain visible without overriding availability FAIL. A database/combined case with failed full-phase availability receives overall FAIL. Historical App Service recovery-only PASS labels retain their component attribution; they do not define overall AKS acceptance.

AKS nine-node/six-pod placement, private HTTPS/authentication/idempotence/checksum smoke checks and non-fault native validations passed qualification. BASE-001 passed with 100% business success and successful-operation p95 11 ms. Every measured fault case then failed a required gate; final private qualification passed separately. Keep DNS, ingress timing, local tunnel and pre-load singleton-selection repairs in troubleshooting elapsed time; they supply no fault-test downtime or recovery measurement.

The initial node preparation attempt stopped before load/injection. Its retry is an actual native fault execution, with native completion, independent caller/object-claim attribution and at least 300.292 s sustained power-off verified. Do not merge the preparation failure with measured fault errors or derive a complete HA PASS from baseline/native completion.

### Original node case: aggregate and required-window availability

The twelve-minute phase recorded 14,307 successful and 93 failed logical business operations, for 99.3541667% success, passing its configured 99% full-phase threshold. The exact first 300 seconds after observed power-off recorded 75 failures among 6,000 operations: 98.75%, below the required 99%. The original case remains FAIL. Successful-operation p95 11 ms and zero complete canary unavailability do not cancel the logical-success failure.

Publish 348 raw failed attempts separately from 93 failed logical operations; retries make these different denominators. Record zero business/canary drops and 721 successful, zero failed canary ticks. Full-phase aggregation can dilute the disruption interval; it cannot replace the exact post-effect gate. Baseline/stable 99.9% thresholds also remain unchanged.

Offline independent evaluation passed recovery at 47.434 s into a complete qualifying 60-second window and passed 300-second stability. Retention reconciliation took 97.7048 s; workload measurement took 731.188 s and the whole case 1,026.2697 s. These time categories remain separate. Recovery/stability PASS does not erase availability/final-placement FAIL, and an availability failure must not hide the independently qualified recovery results.

### Corrected twelve-minute node case and stability horizon

The corrected case passed first-five-minute business success at 99.4666667% (32 failures among 6,000 operations), p95 11 ms and a maximum one-second complete canary outage. At least 303.8277 s exact-node power-off, recovery at 0.732 s and automatic final nine Ready nodes/six Ready pods/six distinct workers/three zones passed. Full-phase business success was 99.5625304%, with 63 failed logical operations and 402 raw failed attempts; canaries recorded 718 successes/3 failures and no drops.

None of 362 complete candidate 300-second stable windows qualified. Late failures through 12:22 left less than five stable minutes before measurement ended at 12:25:24. The corrected case remains FAIL; short recovery and restored placement cannot override stability failure.

Initial analysis INCONCLUSIVE resulted from an expected unscheduled Pending replacement lacking `nodeName`. The repaired evaluator skips only unscheduled Pending pods and rejects unscheduled non-Pending pods. Saved raw data was re-evaluated without resubmitting the fault, and the initial verdict remains in history. Fixtures pass and stable FAIL now propagates FAIL rather than INCONCLUSIVE.

All subsequent fault load phases use eighteen minutes with bounded twenty-minute observers, retaining first-five-minute thresholds, rates, VU caps and seven-minute native shutdown. This is an observation-horizon change, with unchanged architecture/image and qualified baseline. Full-phase denominators will differ; preserve twelve-minute results separately and do not infer an eighteen-minute PASS before measurement.

### Completed eighteen-minute node case

The eighteen-minute case had 63 failures among 6,000 exact first-five-minute business operations: 98.95%, below 99%. At that denominator, 60 failures is the maximum allowed; three additional failures constitute a real FAIL. Successful-operation p95 11 ms, no drops and maximum one-second complete canary outage passed their separate gates.

Native/audit, 306.1511 s sustained shutdown, recovery 39.181 s, automatic six-worker/three-zone placement and all-history retention passed. The stable window 12:50:35–12:55:35 passed with 5,994/6,000 business successes (99.9%), 300/300 canaries and p95 11 ms. The full phase passed its recorded aggregate gate at 99.5509467% success.

Longer observation fixed missing stable-window coverage; it did not fix the exact availability miss or erase the earlier twelve-minute stable FAIL. The root of recurrent late eight-second transport failures remains unproven. Preserve measured failures rather than repeatedly injecting until a favorable result, and record any future investigation as separately justified work.

Raw NODE18 diagnostics show 458 failed business attempts plus 51 failed canary attempts, all status 0 and approximately eight seconds long, recurring from 12:42–12:52. These observed transport symptoms do not prove a DNS, TLS, load-balancer, connection-pool or platform root cause.

### Completed selected-zone compute case

Exactly three selected VMs, system-zone-1/z1a/z1b, were independently off for 304.0433 s; the other six remained running and traffic continued in logical zones 2/3. Native execution/authenticated audit passed. This establishes the planned lab-owned zonal compute effect, while broader physical-zone infrastructure and managed dependencies retain their separate scope limits.

First-five-minute business success was 97.85% (129 failures among 6,000), with 300 expected canaries, no drops, p95 11 ms and maximum one-second complete canary outage. Full-phase success was 98.9629630%, below its 99% threshold. Both business-success gates fail despite passed latency/canary-gap gates.

Recovery passed at 64.320 s; the 13:17:41–13:22:41 stable window passed at 5,994/6,000 business successes, 300/300 canaries and p95 11 ms. Automatic final six-worker/three-zone placement and complete-history retention passed. The overall case remains FAIL.

AKS reconciliation verified 21,594 acknowledged writes/seven history runs after NODE18, 26,966/eight after zone and 32,330/nine after DB, with zero loss/checksum mismatch. Keep progressive AKS counts separate from App Service's 92,616 writes/31 historical runs.

### Reconciled database case and interrupted topology observation

The database native operation and declared Workspace identity authentication passed. Initial pipeline FAIL came from a topology observer exiting on one ten-second ARM GET timeout. The dependency observer and load completed; original verdict and interrupted topology trace remain preserved. Unchanged raw load/health/topology evidence and complete-history retention were retrieved/reconciled in place without another fault.

Database effect/recovery/stability/role swap passed using the complete independent dependency probe and actual role inventory. Recovery was 28.551 s to the complete sixty-second window starting 13:34:19; stable service from 13:34:19–13:39:19 passed. These sources do not retroactively complete the interrupted topology trace or establish unobserved compute states.

Full-phase business success failed at 98.0093514% against 99.9%: 21,171 successful operations, 317 logical failures and **113 business drops**. Canaries recorded 1,051 successes, ten failures and **20 drops**. Dropped scheduled work remains in the availability denominator. Successful-operation p95 13 ms excludes failures/drops and cannot establish low-impact failover by itself. Overall FAIL remains despite recovery and retention PASS.

Future known transient ARM timeouts/429/5xx are diagnosed explicitly; discard the entire incomplete sample and continue the next bounded observation. Preserve the unchanged 30-second maximum gap and fatal unauthorized-error behavior. Retrieve load/retention evidence before reporting observer failure. Actual catch-handling fixtures passed; this repair supplies no missing historical topology data.

Combined completed overall FAIL at 97.4445628% full-phase success against 99.9%, including 118 business/20 canary drops. Both observers exited 0. Native/authenticated identity, three-VM effect for at least 300.1613 s, independent overlap, recovery 28.855 s, stability, retention and final placement passed. This completed trace does not retroactively complete the interrupted standalone DB topology observer.

## App Service process-crash scope

The measured Windows Actions killed application dotnet worker processes on one exact App Service instance and on both instances associated with the selected physical zone. App Service restarted those processes in place. The workers' instance identities and zone placement persisted through the measured effects.

Those experiments establish routing and recovery during discrete process loss under the recorded load. They leave the App Service worker hosts, zone infrastructure, ingress and shared networking outside the demonstrated fault effect. The 11–13 s or 12.7 s process-start intervals describe process replacement timing; zero business failures describe the independent client outcome.

Windows native validation rejected an explicit `processName`. The scenarios omitted it, and out-of-process hosting allowed the measured default target to be the dotnet application worker. Eligibility of that runtime/hosting combination needs requalification before reuse.

### Linux support evidence

Where process listing succeeded on .NET 8, .NET 9 and Node.js 22, actual deletion returned HTTP 400 `This runtime stack is not yet supported on Linux`. Other tested stacks encountered listing blockers: .NET 10/11 returned 409 through dotnet-monitor, Python 3.13/Java 21/container listing returned 400, and Node.js 24 listed no processes.

Listing success, selector validation and a documented template each cover distinct prerequisites. Actual unsupported deletion left Linux application and combined coverage BLOCKED. Windows outcomes apply to the Windows variant.

### Windows connection-open finding

Npgsql's `GSS Encryption Mode=Prefer` caused Kerberos/SSPI probing during cold physical opens on Windows App Service. Measured physical-open time fell from 4.7–5.1 s to 0.22–0.60 s after disabling GSS encryption probing. TLS certificate/hostname verification and Entra token authentication remained unchanged.

This finding addresses the observed Windows cold-open stall. It supplies no general database-failover guarantee and should retain its platform attribution when comparing with the .NET 10 AKS container.

## PostgreSQL forced failover

The App Service database case exercised a native forced failover, role/zone transition and application reconnection. Recovery and durability passed at 36.359 s. Full-phase availability failed at 97.347%. The combined case recorded 34.989 s recovery and 97.324% full-phase availability.

Those outcomes show that all acknowledged writes survived and service recovered under the measured load, while some scheduled operations failed or were dropped during disruption. Latency percentiles for successful operations exclude failed requests; publish failures, dropped operations and canary gaps alongside p95.

A managed forced failover leaves the underlying host-failure and physical-zone-loss mechanisms outside directly demonstrated coverage. For the AKS comparison, record the actual failover mode, primary/standby transition, accepted native operation, observed dependency failure and recovery separately.

## Combined overlap

The Windows combined case observed database disruption first, then submitted the process kill. Independently observed database failures bracketed process replacement, with no healthy sample between the bracketing failures. This supports the reported overlap within the observation resolution.

The AKS combined case used database-first triggering and independently observed dependency failure during actual selected-zone node shutdown. Power-off at 14:03:09.8203411 UTC was bracketed by database 503 requests at 14:03:02.2493908 and 14:03:15.5460861 (the latter response at 14:03:16.5696703), with no intervening healthy dependency observation. This proves overlap within the recorded observation resolution; simultaneous submissions alone were not used as proof.

Recovery passed at 28.855 s from first database disruption to the complete sixty-second window beginning 14:03:19. Stable service passed from 14:12:12–14:17:12, with 5,994/6,000 business successes, 300/300 canaries and p95 11 ms. Overall FAIL remains despite these gates passing.

## AKS compute shutdown and physical-zone scope

The new native fault path targets node VM scale sets. The selected live Action accepts `GracefulShutdown` and `Zones`; it has no instance-ID parameter.

| Intended experiment | Required target/effect evidence | Coverage boundary |
| --- | --- | --- |
| Exact application node | One owned single-node user-pool VMSS mapped to one Kubernetes node; actual power-off and NotReady | One application compute node and its workloads |
| Selected-zone compute | Exactly three owned VMSS: system, z1a and z1b selected with zone 1; expected two user nodes and one system node physically off | Lab-owned AKS compute in the selected zone |
| Database forced failover | Native operation, observed dependency errors, role/zone transition | Managed database failover and application reconnection |
| Combined | Database failure independently overlaps actual selected-zone node shutdown | Correlated tested dependency/compute effects |
| HA-AZ-001 | Supported broader physical full-zone injection and independent effect proof | Remains BLOCKED; no physical full-zone injection is planned |

The private internal load balancer, shared networking and AKS control plane are outside the planned physical fault targets. A concurrent PostgreSQL forced failover adds a tested dependency effect, while ingress, network, control-plane and managed-host disaster behavior remain unverified.

### Sustained window and service remediation

Require a continuous five-minute (at least 300-second) physically-off interval, supported by ARM VM power-state snapshots and Kubernetes NotReady observations. The native definitions use `PT7M` to provide sampling margin despite provider startup/restoration overhead. Seven configured minutes still require proof of the actual continuous outage. Correlate each VMSS node with its Kubernetes identity, physical zone and workload placement. Readiness alone cannot establish power-off: a node can become NotReady because of connectivity or reporting delays.

Selected-zone targeting includes the system VMSS and only the zone-1 user VMSS, z1a and z1b. `Zones=['1']` selects the single zone-1 system instance from the three-zone system pool. Excluding the other four user VMSS avoids empty-zone selector matches. Verify actual mapping before execution and block unexpected extra/missing targets.

The independent runner's node-group Reader role supports ARM power-state observation. The Chaos identity's node-group Virtual Machine Contributor and Reader roles support mutation and reads. Role assignment does not prove a successful shutdown or complete evidence; record effective access and actual fault callers separately.

### Native identity metadata discrepancy

For the actual exact-node retry, independent target-operation caller and object claims verified the declared Chaos Workspace user-assigned managed identity despite incorrect reported-principal metadata. Preserve both the metadata discrepancy and successful independent audit. This strengthens operation attribution without resolving every provider field or proving fault duration, service recovery, retention or restored-health qualification.

Use the independently verified operation evidence for the attributable case; do not treat the discrepancy as a blanket waiver for missing or ambiguous identity/target evidence on later Actions.

Record the actual shutdown state, including whether the service stops or deallocates instances, the configured `GracefulShutdown` value, and the verified restore-on-stop behavior. Verify restoration after Action completion or abort. Action duration by itself supplies no continuous-effect proof.

Static pools, disabled autoscaling and disabled NAP make the intended capacity explicit. AKS reconciliation or remediation may still restart or replace nodes. Record every replacement, power-state transition and pod reschedule. A restart or replacement that shortens the required five-minute fault window fails the sustained-fault gate, even when business availability remains good.

The original node case restored nine Ready nodes and six Ready pods automatically but only five distinct application workers: two pods on z1b and none on the returned z1a. This is a failed baseline-placement restoration gate. Surviving traffic in all three zones supplies evidence of remaining zonal participation, while six-worker restoration requires one healthy participating pod on each distinct user node.

### Live post-measurement correction and remaining evidence

Hard hostname pod anti-affinity is live to prevent replacement replicas from co-locating on surviving user nodes. With six static user nodes and six desired replicas, one or two unavailable user nodes should leave one or two replicas Pending and five or four serving. Corrected-node and selected-zone automatic six-worker/three-zone restoration and eighteen-minute stability passed; neither result overrides their availability FAIL.

Private Service `externalTrafficPolicy: Local` with five-second/two-probe health settings is live. The actual Azure ILB HTTP `/healthz` node-port probe qualified with `numberOfProbes=2`, `probeThreshold=2` and state Succeeded. The original Cluster policy allowed cross-node forwarding and stale-endpoint routing exposure. Local policy changes the routing contract and health evidence; it does not guarantee immediate failed-node withdrawal or a maximum five-second outage. Verify endpoint availability, probe/propagation delays and corrected fault request results.

The normal post-measurement apply/rollout/qualification completed at 11:46:14 UTC in 67.7708 s. Fresh corrected baseline passed. Corrected-node execution/audit, effect, recovery, placement and retention passed, but stability failed. Both original and corrected twelve-minute FAIL results, thresholds, private IP, TLS, immutable image/business revision, six replicas, six user pools and three physical zones remain preserved. No restart or correction occurred during original native measurement; setup rollout cannot retroactively count as automatic recovery.

Bicep/private invariants, native contracts and effect fixtures passed for the preparation; fixtures preserve separate availability/recovery/stability gates. Owned server dry-run/diff limited changes to Deployment anti-affinity, Service Local/probe settings and server-allocated `healthCheckNodePort`. Baseline/placement PASS, twelve-minute stability FAIL and eighteen-minute availability FAIL remain separately attributed.

Ownership validation also compares other-project IDs and resource metadata order-independently, persisting evidence after diagnosis. Tag reordering is accepted; changed tag values are rejected. These guards establish a separate safety boundary and do not supply resilience acceptance.

### Endpoint readiness during dependency failure

The Kubernetes workload readiness probe checks process liveness, retaining endpoints during transient PostgreSQL disruption so the application can handle dependency errors and reconnect. Explicit `/health/ready` remains the baseline/restored-health qualification gate. Kubernetes Ready therefore records the probe's process-health condition; it supplies no independent database or successful-business verdict.

Publish dependency errors and canary/business results throughout failover even when pods remain Ready. The approved recovery objective is 180 seconds to the beginning of a complete 60-second window with at least 99% business/canary success and successful-operation p95 at most one second, followed by 300 continuous stable seconds at 99.9% business success and baseline latency. Endpoint retention supplies no availability PASS by itself.

For compute-only service, evaluate the first 300 post-effect seconds at at least 99% business success and successful-operation p95 at most two seconds, with no complete outage longer than five seconds. The database/combined recovery window and stable window both use successful-operation p95 at most one second.

## Load, durability and comparison boundaries

The planned AKS load is 20 scheduled business operations/s plus one independent canary/s, with bounded maximums of 200 business VUs and 10 canary VUs. Dropped work remains part of the availability record. Preserve the offered rate, request mix, payload size, deadlines, build identity and observation cadence for comparison.

Reconcile every acknowledged write and checksum across the complete attributable history. The App Service total of 92,616 writes belongs to its 31 historical runs. AKS totals must be measured and reported separately; no new retention success is inferred from the older total.

The comparison changes hosting platform, runtime, ingress and compute fault mechanism. Report these changes rather than attributing every difference in availability to one platform choice. Baseline checks, elapsed provisioning/troubleshooting/measurement time, and full-phase denominators must accompany final conclusions.

The historical App Service lab queried telemetry through AMPLS. Initial AKS templates omit AMPLS and application Log Analytics; application logs use the private Kubernetes API and independent runner observers. Raw business measurement logs remain private under ignored `.local\`. Actual Defender security telemetry has the separate exception below. Publish sampling cadence/missing intervals; lost API/log access cannot itself prove node power-off.

## Managed security telemetry and external scope delta

Read-only live inspection found AKS Defender `securityMonitoring.enabled=true` and `securityGating.enabled=true` referencing a default regional Log Analytics workspace. `addonProfiles` and `azureMonitorProfile` are null. Workspace public ingestion and query are Enabled; these settings leave all-security-telemetry privacy unqualified even though workload/API/PG/ACR/KV private paths and business measurement evidence remain qualified.

The original 24 unrelated resource IDs and **complete returned metadata** are unchanged. Protected inventory now contains **25** resources after one default workspace appeared at **10:56:57 UTC** in a pre-existing regional group outside the four owned lab groups. The delta safeguard is **FAIL**. An unchanged original set does not establish an unchanged total footprint.

Correlated workspace Started/Accepted/Succeeded Activity Log writes independently authenticate the subscription's Defender for Containers managed identity. The actual AKS Defender profile references the created workspace. This proves governance-managed creation, with exact IDs/claims retained only in ignored evidence. No PC command explicitly created, modified or deleted the workspace/group or changed governance for this finding; leave the external group untouched for operator review.

Proven managed creation does not establish lab-manifest ownership or remove the extra-resource delta. Do not weaken the hard guard, adopt the workspace into the owned manifest, automatically delete it, disable governance or renew an exemption. Separate service measurement outcomes from resource-scope and security-telemetry qualification. The updated SVG explicitly depicts this governance-managed public telemetry destination outside four owned groups; it supplies no whole-environment telemetry-privacy proof.

## Lifecycle and retention

The App Service dedicated groups were deleted by the operator on 6 November at 09:43 UTC; seven unrelated groups and 24 resources were verified unchanged. Historical execution reports describe resource state at their original evidence time.

The new AKS lab remains active until the operator orders stop or deletion. No independent expiry enforcement is claimed. Resource-group absence alone does not establish deletion of retained backups, audit records or recoverable vault objects.

Final private qualification and retention PASS establish the final observed workload state and 37,659/37,659 acknowledged writes across ten runs. They do not erase fault acceptance FAILs, HA-AZ-001 BLOCKED or external scope delta FAIL. The final real-zone guard exits 1 without injecting or changing Azure.

Final owned inventory has 87 resource/definition/exemption IDs across four active groups; it is not a top-level resource count. On an operator deletion order, remove workload/AKS first, let AKS delete the managed node group and verify absence, then operations and network. Never delete the pre-existing default regional group or Defender workspace. See the [cleanup order](aks-lab.md#operator-managed-cleanup-order).

Only the temporary PC tunnel helper was stopped. Azure resources remain running/active; helper shutdown establishes no Azure suspension or cleanup verdict. Exact inventory/private-access restart instructions remain in ignored `.local\<run>\OPERATOR-RESULTS.md`, with manifest/handoff preserving final FAIL, health PASS and retention PASS.

## Timing interpretation

Manifest creation to final read-only verification was 18,336.744344 s, while ten unique k6 intervals totalled 7,677.297 s. Recorded case-retention time is an incomplete 859.3913 s subtotal excluding unrecorded initial-baseline retention and manual DB reconciliation. Parallel infrastructure children overlap each other and the parent; do not add them together.

Research, authorization, diagnosis, manual reconciliation and operator gaps are not fully timed. Keep unclassified elapsed time honest rather than assigning it to invented active work. See the [final timing table](aks-results.md#elapsed-time-and-attribution).

## Official fault-scope references

- [Chaos Studio AKS guidance](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance)
- [Chaos Studio Scenarios](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios)
- [Workspace supported resources](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [AKS Standard Load Balancer](https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard)
- [Azure cloud-provider custom health-probe annotation table](https://cloud-provider-azure.sigs.k8s.io/topics/loadbalancer/#custom-load-balancer-health-probe)

Supported catalog entries, exact live Action parameters and observed effects must be recorded together; documentation alone supplies no execution verdict.
