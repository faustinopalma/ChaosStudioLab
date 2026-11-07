# Private AKS and PostgreSQL comparison lab

[Lab guide](lab-guide.md) · [Limits](experiment-limits.md) · [Results](aks-results.md) · [Decision D24](../DECISIONS-ACCEPTED.md#d24-private-aks-comparative-architecture-and-operator-authorization)

Final evidence date: 7 November 2026. Baselines and final private qualification passed. Every measured fault case remains FAIL at a required gate, including combined full-phase availability despite proven overlap/recovery/stability/retention. Original interrupted topology evidence is preserved; physical full-zone HA-AZ-001 remains BLOCKED. See [final results](aks-results.md).

[Open the editable private AKS architecture SVG](diagrams/06-private-aks-zone-lab.svg). It shows the workload data plane, one-pod-per-host placement, Local health probes and lab-owned compute fault boundary. The updated drawing explicitly shows the governance-managed public telemetry exception outside the four owned groups. Earlier structural/browser-render checks passed; the telemetry exception and scope delta are described below.

## Objective and operating scope

Reuse the current application's committed-write/checksum model to compare private AKS service behavior with the measured App Service history. Add controlled infrastructure-node loss and sustained selected-zone compute loss, retaining separate availability, recovery, overlap and durability verdicts.

The operator authorized autonomous implementation, deployment, necessary repairs and testing. Work is orchestrated from the PC in bounded foreground stages with visible progress and logs. One private Ubuntu runner uses managed identity for publication and measurement. The later operator instruction authorizes exact-owned teardown after successful native-suite reruns; preserve unrelated resources and ownership checks.

## Regional and platform qualification

| Item | Selected value or qualified prerequisite |
| --- | --- |
| Region | Sweden Central |
| Compute catalog | `Standard_D4ds_v5`, live unrestricted qualification in zones 1, 2 and 3 |
| Initial alternative | Italy North VM candidate restricted |
| AKS tier | Standard |
| Kubernetes/runtime OS | Live AKS 1.35.9 on Azure Linux 3.0 |
| Provisioning model | Static VMSS node pools; NAP and cluster autoscaling disabled |
| Networking | Azure CNI Overlay with Cilium |
| Application runtime | Six live .NET 10 pods using existing application source and a pinned private ACR digest |
| Database | PostgreSQL Flexible Server 16; regional zone-redundant HA capability enabled |

AKS Standard was selected to use the supported VMSS node-fault path without NAP. Live qualification verified node allocation, six-pod placement, private connectivity and authenticated smoke participation. Repeat those prerequisites for each measured run; qualification and non-fault validation do not establish baseline availability or actual fault effects.

## Private architecture

| Component | Intended path and responsibility |
| --- | --- |
| AKS API server | Private API access; public FQDN disabled; administration from the private runner |
| Application ingress | Private HTTPS through an internal load balancer; qualified Local traffic policy and HTTP `/healthz` node-port probe at five seconds/two probes |
| Premium Azure Container Registry | Private endpoint; managed-identity build/publication and kubelet pull access |
| Key Vault | Private endpoint; managed-identity access to required application/runner material |
| PostgreSQL 16 | Private endpoint, disabled public data-plane access, Entra-only authentication, verified TLS |
| PostgreSQL HA | Zone-redundant; intended primary zone 1 and standby zone 2; verify live Healthy role placement |
| Private DNS | Resolution for registry, vault, database, API and application from their required callers |
| Application logs | Private Kubernetes API and runner observations; initial templates omit AMPLS/application Log Analytics |
| Managed security telemetry exception | Enabled Defender monitoring/gating references external default Log Analytics with public ingestion/query Enabled; subscription Defender managed-identity creation independently proven |
| Private Ubuntu runner | Managed-identity publication, migrations, k6 measurements, independent observer and node-topology monitor |
| PC orchestration | Bounded foreground stages and visible local logs; raw lab measurement evidence retained under ignored `.local\` |

Managed-identity authorization and private network reachability need independent checks. A build service reaching a private registry also needs a verified network path; granting registry permissions alone cannot qualify publication. Record the actual build location and private push/pull proof.

The planned comparison preserves application logging and independent observations without adding application Azure Monitor services. This differs from the historical App Service AMPLS query path. Actual inherited/managed security telemetry requires separate qualification: live AKS `securityProfile.defender.securityMonitoring.enabled=true` and `securityGating.enabled=true` reference an external default regional workspace. `addonProfiles` and `azureMonitorProfile` are null; those null profiles do not remove the Defender reference. Workspace public ingestion and query are Enabled, so no all-telemetry-private claim is supported.

Read-only scope verification found original 24 unrelated IDs/complete returned metadata unchanged plus one workspace created at 10:56:57 UTC in a pre-existing group outside four owned lab groups. Correlated Started/Accepted/Succeeded Activity Log writes independently authenticate the subscription's Defender for Containers managed identity; the actual AKS Defender profile references the created workspace. Managed attribution is proven. Inventory is 25 and delta guard remains FAIL; external creation is not lab manifest ownership.

No PC command explicitly created/modified/deleted that workspace/group or changed governance. Leave the group untouched for operator review, preserving the hard guard; do not adopt the resource into the owned manifest or automatically delete/disable governance/renew an exemption. Exact identifiers/claims remain private.

Application HTTPS, AKS API, PostgreSQL, registry and vault private paths remain qualified. Raw business measurement logs stay private. Treat managed security telemetry and external resource attribution separately from these workload data-plane checks.

Live private API, PostgreSQL, ACR and Key Vault DNS checks resolved inside approved subnets. Private application HTTPS returned 200; authentication, idempotence and checksum smoke checks passed using the existing digest-pinned image. The PC's Bastion tunnel uses local port 40222 after Windows rejected 50222 with `WinError 10013`; SSH and private API access were verified through the same Bastion path.

The independent runner receives Reader at the owned AKS node resource group, enabling ARM node/VMSS power-state reads without compute mutation authority. The Chaos identity receives Virtual Machine Contributor and Reader at the same boundary for native shutdown and reads. Verify effective role assignments and actual operation callers independently of fault effects; these roles do not replace private API or application authorization.

## Node and workload placement

The qualified topology contains **nine Ready nodes across seven VMSS**:

- Three dedicated system nodes distributed across zones 1, 2 and 3 and tainted to keep the application on user nodes.
- Six single-node user pools, each pinned to one zone and held at count 1.

The following names are logical pool labels; they disclose no deployed resource identifiers.

| Logical user pool | Zone | Node count | Baseline application pods |
| --- | ---: | ---: | ---: |
| z1a | 1 | 1 | 1 |
| z1b | 1 | 1 | 1 |
| z2a | 2 | 1 | 1 |
| z2b | 2 | 1 | 1 |
| z3a | 3 | 1 | 1 |
| z3b | 3 | 1 | 1 |

Configure topology spread for six baseline application pods across six user nodes and three physical zones. Qualify the actual placement, readiness and authenticated business participation of each pod; a desired replica count alone cannot establish six-node participation.

Live qualification observed six pods, one per user node. Logical zones 1, 2 and 3 mapped to `swedencentral-az1`, `swedencentral-az2` and `swedencentral-az3`. The subsequent ten-minute baseline passed at 100% business success with successful-operation p95 11 ms. Recheck this placement and build identity before each injection.

The baseline gate requires the expected node set, one system and two user nodes per zone, six application pods on six distinct user-node hostnames, and the expected application build. Record system-pool layout from the deployed inventory without assuming one VMSS per system node. Record actual rescheduling and remediation rather than equating Ready replica count with restored baseline placement.

### Qualified post-measurement scheduling and routing correction

The original measured node fault recovered nine Ready nodes and six Ready pods automatically. However, two application pods remained on z1b and none on the returned z1a, leaving five distinct application workers. Ready-node and Ready-pod totals therefore missed the six-worker placement requirement.

Live hard pod anti-affinity on `kubernetes.io/hostname` requires at most one application pod per user node. Retain six desired replicas and the existing user-node restriction. During single-node loss, five pods should serve and the sixth should remain Pending; during selected-zone loss, four should serve and two remain Pending. When the affected nodes return, normal scheduling must restore six distinct healthy workers without a manual application restart. Requalify per-worker authenticated participation and physical-zone spread.

The private Service correction uses `externalTrafficPolicy: Local` with supported five-second health-probe interval and two-probe failure settings. Local traffic policy restricts ingress forwarding to node-local endpoints, allowing the load balancer's backend health to reflect local endpoint availability rather than Cluster policy's cross-node forwarding. This targets stale-node/stale-endpoint routing during power loss. Verify actual generated probes, backend withdrawal, endpoint transitions and request evidence after rollout; probe settings do not prove an exact outage bound.

**Correction status: live and qualified since 11:46:14 UTC.** Post-measurement apply/rollout/qualification took 67.7708 s. The actual Azure ILB probe was HTTP `/healthz` on its allocated node port, interval 5 s, `numberOfProbes=2`, `probeThreshold=2`, state Succeeded. All six distinct workers/three observed zones and per-pod health/checksum traffic qualified. Private IP, TLS, immutable image/business revision, six replicas, six user pools and thresholds remained unchanged.

Fresh corrected BASE-001 passed and its final six-worker/three-zone placement requalified. The corrected twelve-minute node retry began load at 12:13:10 UTC, with native acceptance at 12:13:59. Native execution/audit, first-five-minute availability and automatic placement passed; 300-second stability failed. Preserve both node FAIL cases and their distinct gates. Post-measurement rollout supplies no substitute for automatic recovery during a fault.

The prepared configuration passed Bicep/private invariants, native contracts and effect fixtures, including preservation of availability FAIL alongside recovery/stability PASS. Actual owned Kubernetes server dry-run and diff passed: only Deployment pod anti-affinity, Service Local/five-second/two-probe settings and server-allocated `healthCheckNodePort` change. Namespace, service account, PDB, immutable image/runtime source and private IP remain unchanged.

The qualifier guards actual Service and anti-affinity configuration. Server dry-run/diff preceded rollout and remains separate from live qualification. Corrected-node sustained outage and automatic placement passed. The completed eighteen-minute case also qualified stability, while its exact first-five-minute availability failed.

### Immutable read cache and ingress protocol repair

The 7 November follow-up keeps the private load-balancer topology, six distinct workers, PostgreSQL commit acknowledgements and all measurement thresholds. Its two application-path changes are enabled only by the AKS Deployment:

- `Orders__CacheImmutableReads=true` enables a bounded per-pod cache of up to 10,000 confirmed immutable order records, with one-hour expiry. Positive reads and successfully committed writes populate it. Missing rows, failed writes and unknown outcomes are never cached. Every write/replay still reaches PostgreSQL; dependency health checks remain uncached.
- `Kestrel__EndpointDefaults__Protocols=Http1` selects HTTP/1.1 for AKS TLS ingress. Live read-only diagnosis confirmed the previous path negotiated HTTP/2. Standard Load Balancer withdraws unhealthy backends for new connections while established TCP flows retain their separate lifetime. The repair tests whether HTTP/1.1 request cancellation/reconnection removes the recurring eight-second transport failures observed during node loss; the causal comparison requires new measured runs.

The immutable read model avoids a PostgreSQL round trip for repeatedly requested confirmed orders. Cache misses and writes preserve the existing five-second server deadline and explicit transient-error handling. The client retains its original request mix, eight-second HTTP attempts, 180-second bounded write reconciliation, offered rates and VU caps. Failed attempts and dropped operations remain visible.

Application HTTP responses and persisted SQL verification retain their existing contracts. The cache supplies process-local availability for immutable reads; committed SQL remains the durable authority. Eviction, a cold pod or an uncached ID still requires database availability. The default App Service variant leaves the cache disabled and retains its existing protocol configuration.

Private qualification verifies actual Deployment flags, HTTP/1.1 traffic and authenticated cache counters on every pod. Load evidence now includes negotiated protocol and transport error codes. Unit tests cover outage reads, missing rows, cancelled reads and write/health operations that continue to require the database. The .NET test project follows the API's optional `LabTargetFramework`, preserving its default .NET 9 target while validating the current AKS .NET 10 runtime.

The AKS retention verifier captures a separate direct PostgreSQL snapshot of order IDs and stored checksums using the existing migration managed identity, VerifyFull TLS and a bounded read-only query. Every issued/acknowledged operation is reconciled against that SQL snapshot, with source and snapshot hash retained in each verdict. Cached API reads continue to test business behavior; they provide no substitute for independent SQL retention evidence. Missing acknowledged rows, changed hashes, malformed snapshots or SQL failures explicitly fail verification.

### Workload readiness and qualification

The workload readiness probe checks process liveness, retaining application endpoints during transient database failure. This permits the API to handle bounded dependency errors and reconnect without withdrawing every endpoint solely because the shared database is failing.

Explicit `/health/ready` remains the baseline and restored-health qualification gate, alongside authenticated business operations, canaries and PostgreSQL role health. A Kubernetes Ready pod alone cannot qualify database-dependent service availability. Record probe configuration and dependency errors throughout the fault; endpoint retention supplies no success verdict.

## Native shutdown targeting

The selected live native node VMSS shutdown Action exposes `GracefulShutdown` and `Zones`, with **no instance-ID selector**. Preserve its exact live contract and accepted parameters in private evidence. Do not introduce an unsupported instance selector.

Native shutdown definitions use **`PT7M` (seven minutes)**. This provides margin for independent power-state samples to demonstrate at least **300 continuous seconds** physically off despite provider startup/restoration overhead. Definition duration and observed fault duration are separate facts.

### Exact node

Select one owned user-pool VMSS containing exactly one live VM instance. Correlate that instance with its Kubernetes node, physical zone and baseline application pod. The single-node pool shape provides the exact-node boundary. Block execution if the VMSS contains extra instances or no longer matches the baseline.

### Selected-zone compute

Enumerate the owned AKS system and user VMSS to establish complete node/zone mapping, then target **exactly three VMSS** with `Zones=['1']`: the system pool and logical user pools **z1a and z1b**. The selector includes only the zone-1 system VM from the three-zone system pool, plus the two single-node user pools. Exclude z2a, z2b, z3a and z3b, avoiding empty-zone matches.

The expected affected set is three nodes: the two user nodes in zone 1 and its system node. Verify that every expected node belongs to the exact owned target set and that no unowned VMSS or unexpected instance is included.

Observe a continuous **five-minute physically-off interval** through ARM VM power states and Kubernetes NotReady, while independently confirming healthy surviving pods. Time the sustained window from observed effects on the full intended target set. Record actual stop/deallocation semantics, restore behavior and every AKS reconciliation or remediation event.

A replacement or restart that shortens the required sustained window produces a **FAIL** for that gate. Missing or ambiguous evidence prevents qualifying the effect. Process/pod faults retain separate attribution and cannot substitute for this compute test.

## Test matrix

| Test | Planned load phase | Fault and required evidence |
| --- | --- | --- |
| BASE-001 | 5 min warmup + 10 min baseline | Expected build, private paths, nine-node topology, six participating pods, healthy cross-zone PostgreSQL and complete load samples |
| HA-NODE-001 | 18 min | Exact single-node user VMSS shutdown defined as PT7M; at least 300 s sustained power-off, NotReady, surviving service and verified restoration |
| HA-ZONE-COMPUTE-001 | 18 min | PT7M shutdown targeting exactly system/z1a/z1b VMSS with zone 1 selected; expected three-node effect sustained for at least 300 s |
| HA-DB-001 | 18 min | Native PostgreSQL forced failover; independently observed dependency errors, Healthy primary/standby transition, recovery and retention |
| HA-COMBINED-001 | 18 min | Database-first failover; trigger selected-zone shutdown after observed dependency failure; independently prove business-effect overlap |
| HA-AZ-001 | Guard only | **BLOCKED** until supported physical full-zone injection and independent effect evidence exist; do not inject under the current plan |

Fault duration and load duration are separate measurements. Begin each case only after a successful current baseline and recheck the build, node set, pod participation, private paths and database health. If provider delays consume the observation budget, record incomplete coverage or extend within a separately recorded bounded stage; do not count pre-effect time as post-fault observation.

All fault load phases now use eighteen minutes with bounded twenty-minute independent observers. Earlier original/corrected node phases were twelve minutes and keep their recorded outcomes. The corrected phase had late failures through 12:22, leaving less than 300 stable seconds before it ended at 12:25:24. Extending the horizon allows post-shutdown/restoration stability to be assessed; rates, VU caps, first-five-minute criteria and PT7M shutdown stay unchanged. No architecture/image change or baseline reset precedes the fresh node retry.

The eighteen-minute node retry began load at 12:41:48 UTC, with native acceptance at 12:42:37. Native/audit, 306.1511 s sustained power-off, recovery 39.181 s, 300-second stability, placement and retention passed. Overall FAIL remains because 63 failures among the exact first 6,000 post-effect operations exceed the permitted 60.

The selected-zone case accepted at 13:08:07 UTC verified all three selected VMs off for 304.0433 s, six remaining VMs running and surviving traffic in logical zones 2/3. First-five-minute success 97.85% and full-phase success 98.9629630% failed; recovery 64.320 s, stability, placement and retention passed. This proves lab-owned selected-zone compute effects, while HA-AZ-001 remains BLOCKED. Separate scope guard FAIL is not waived.

Database failover accepted at 13:33:34 UTC executed/audited successfully, then reconciled to overall FAIL at 98.0093514% full-phase success, including 113 business/20 canary drops. Its topology observer interrupted on one ten-second ARM GET timeout; independent dependency observation/load completed. Recovery 28.551 s, stable service and actual role swap passed from the complete dependency trace and role inventory, without declaring the topology trace complete.

Future known transient ARM timeouts/429/5xx are explicitly diagnosed; discard the entire incomplete sample and continue the next bounded observation. The 30-second maximum gap is unchanged and unauthorized errors are fatal. Orchestration retrieves load and retention before reporting observer failure. Catch-handling fixtures passed; unchanged-data reconciliation of the original run does not resubmit a fault or fill missing samples.

Combined completed with both native operations/authenticated identities and both observers passing. The three selected VMs were off for at least 300.1613 s; actual power-off was independently bracketed by database 503 observations without an intervening healthy sample. Recovery 28.855 s, stable service, retention and final placement passed. Overall FAIL remains at 97.4445628% full-phase success against 99.9%, including 118 business/20 canary drops.

An initial exact-node preparation failure occurred before load or injection because singleton VM selection became a scalar. The repaired entrypoint fixture covers both one-VM and three-VM arrays. Keep that preparation attempt separate from the actual retry and its fault measurement.

## Load and acceptance

Use k6 from the private runner with **20 scheduled business operations/s plus one independent canary/s**. Bound concurrency at **200 business VUs and 10 canary VUs**. Preserve the existing request mix and deadlines for comparison, and record their actual values.

| Gate | Acceptance contract |
| --- | --- |
| Baseline and stable service | At least 99.9% business success; successful-operation p95 at most 1 s |
| Compute-only service | First 300 post-effect seconds: at least 99% business success, successful-operation p95 at most 2 s, no complete canary outage longer than 5 s |
| Sustained compute effect | Every intended node physically off for a continuous 5 min, with correlated Kubernetes NotReady and healthy surviving pods |
| Database/combined recovery | Approved objective: at most 180 s from actual dependency disruption to the beginning of a qualifying 60-second recovery window |
| Qualifying recovery window | Complete expected samples; at least 99% business and canary success; successful-operation p95 at most 1 s |
| Stable post-fault period | Continuous 300 s at 99.9% business success and successful-operation p95 at most 1 s; at least 10 min post-effect observation for database/combined cases |
| Operational recovery | Automatic service recovery and restoration of six-worker baseline placement; no manual application restart, endpoint change or database repair to obtain the verdict |
| Full-phase availability | Report the actual configured case threshold separately: the original compute phase used 99%; baseline/stable periods retain 99.9%, and compute-only acceptance retains the exact first-300-second gate |
| Overall case | Any required full-phase SLO or other acceptance-gate FAIL produces overall FAIL, even when native execution/effect/recovery passes; incomplete evidence prevents PASS |
| Durability | Every acknowledged write retained and readable with matching checksum across the complete attributable history |

The sixty-second recovery window is an observation interval. The approved 180-second objective separately bounds the time to its beginning. Report both timings and the 300-second stable window explicitly.

Count scheduled dropped work and independent canary failures in their appropriate denominators. Successful-operation p95 must be labeled and accompanied by failed and dropped counts. Report service recovery separately from node restoration and full-phase availability.

The original node case's 99.3541667% full-phase result passed its configured 99% aggregate threshold, while the first-five-minute window failed at 98.75%. No threshold is relaxed by publishing both: required compute acceptance is still at least 99% over the exact first 300 post-effect seconds, successful-operation p95 at most two seconds and no complete outage longer than five seconds. Keep logical-operation failures separate from raw failed HTTP attempts, including retries.

The eighteen-minute node case likewise passed full-phase success at 99.5509467% while failing the exact first-five-minute gate at 98.95%. A qualifying stable window from 12:50:35 to 12:55:35 passed with 5,994/6,000 business operations, 300/300 canaries and successful-operation p95 11 ms. Longer observation resolves coverage, not the first-window failure. Recurrent late eight-second transport failures have no proven root cause; do not substitute speculation or repeated injections for the recorded outcome.

Selected-zone first-five-minute success 97.85% (129 failures/6,000) and full-phase success 98.9629630% both missed 99%. Its stable window 13:17:41–13:22:41 passed with 5,994/6,000 business successes, 300/300 canaries and p95 11 ms. Preserve overall FAIL even though effect, recovery, stable service, placement and retention pass.

## Evidence and publication gates

For each case retain:

1. Actual build/runtime, supported cluster version, node/VMSS/pod/zone mappings, process-live probe configuration, explicit `/health/ready` qualification and PostgreSQL role state.
2. Exact owned native targets, Action contract, `GracefulShutdown`, PT7M definition duration, zone selectors, scoped observer/Chaos roles, identity/audit correlation and acceptance/completion timestamps.
3. Independent observer and node-topology-monitor samples, actual-effect timestamps, power-state/NotReady snapshots, private-API application logs, surviving pod/business health and sustained-window start/end.
4. Any AKS restart, replacement, reconciliation, rescheduling and service restoration.
5. Raw bounded load samples, offered rate, errors/drops, canary gaps, successful latency and full-phase denominators.
6. Observed dependency disruption, recovery/stable windows and independently bracketed overlap for the combined case.
7. Every acknowledged operation and checksum, complete-history reconciliation, per-gate verdicts and separately attributable elapsed times.

Retain independent effect evidence before final-layout checks, preserving verified shutdown even when restored placement fails. Aggregate the full-phase SLO into the overall case verdict, including database and combined cases. Actual harness AST fixtures exercise PASS/FAIL/INCONCLUSIVE combinations; recovery-only PASS must not become an overall database/combined PASS when availability fails.

Skip only unscheduled Pending pods when mapping transient replacement topology; reject unscheduled non-Pending pods and retain all checks on scheduled pods and final six-worker placement. The corrected case's initial INCONCLUSIVE is preserved, with unchanged-data re-evaluation separately recorded. Stable-window FAIL propagates overall FAIL rather than INCONCLUSIVE; a new eighteen-minute injection is a fresh case.

The owned-resource guard compares all other-project resource identifiers and metadata order-independently and persists evidence after diagnosis. Fixtures accept tag-order changes and reject modified tag values. No service PASS weakens this ownership requirement.

Keep raw identities, resource names, accounts and lab measurement evidence under ignored `.local\`. Publish sanitized counts, zone labels, timings, exact fault semantics and verdict reasons in [AKS results](aks-results.md). The [experiment limits](experiment-limits.md) remain part of any comparative conclusion.

The original node case's completed native Action passed independent caller/object-claim auditing against the declared Workspace user-assigned managed identity, while provider-reported principal metadata disagreed. At least 300.292 s sustained power-off and all-history retention passed independently. Offline evaluation separately passed recovery at 47.434 s into the qualifying 60-second window and 300-second stability. Availability and six-worker restoration failed. Preserve the discrepancy and every original per-gate outcome.

## Original final state and current operator boundary

Final private qualification passed nine Ready Azure Linux nodes, six Ready distinct user workers across three physical zones, AKS Running/private API/public FQDN disabled, and PostgreSQL Ready/Healthy zone-redundant HA with primary zone 1, standby zone 2 and public access Disabled. Complete-history reconciliation retained all 37,659 acknowledged writes across ten runs with zero loss/checksum mismatch.

Final owned inventory records 87 resource/definition/exemption IDs: network 17, workload 42, operations 11 and AKS-managed nodes 17. These categories include definitions/exemptions; do not interpret them as 87 top-level service resources. Four owned groups are left active.

The original series left all Azure lab resources running/active and stopped only the temporary PC Bastion helper. The subsequent repair reopens private management; teardown is now authorized after successful native-suite reruns. Restore private management access using the ignored `.local\<run>\OPERATOR-RESULTS.md`; exact group names/87 IDs and restart instructions stay private.

Original 24 unrelated IDs/complete returned metadata remain unchanged plus the proven Defender-created external workspace. Strict scope delta remains FAIL; public managed security telemetry is disclosed. No external cleanup or governance changes were performed. HA-AZ-001's final guard remains BLOCKED and exits 1 without a fault or Azure mutation.

## Operator-managed cleanup order

Cleanup requires an explicit operator order; it is not an automatic final stage.

Use the ignored `.local\<run>\OPERATOR-RESULTS.md` for exact owned names/IDs and private operational steps; the order below is deliberately generic.

1. Preserve private evidence and recheck the current ownership inventory, acknowledged-write retention, dependencies and known external delta. Do not weaken the guard or extend the manifest to the Defender workspace.
2. Delete the owned workload scope/AKS first. Let AKS remove its managed node resource group as part of service deletion; do not delete that group independently as a shortcut.
3. Verify workload/AKS and managed-node-group absence, including deletion completion, before removing dependent operations resources.
4. Remove the owned operations group, then the owned network group, after dependency/ownership checks.
5. Recheck unrelated original resources and report any retained backups, audit data or recoverable vault objects separately.

**Never delete the pre-existing default regional group or its Defender-managed workspace.** Leave that external scope for operator/governance review. Group absence alone cannot certify service-retention purge or whole-subscription cleanup.

Provisioning, configuration repair, measurement, reconciliation and cleanup have separate timing categories. [Final timing attribution](aks-results.md#elapsed-time-and-attribution) preserves parallel-stage overlap, incomplete retention totals and unclassified elapsed time.

## Official references

- [Chaos Studio guidance for AKS](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance)
- [Chaos Studio Scenarios](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios)
- [Resources supported by Chaos Workspaces](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [AKS Standard Load Balancer](https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard)
- [Azure cloud-provider custom load-balancer health probes](https://cloud-provider-azure.sigs.k8s.io/topics/loadbalancer/#custom-load-balancer-health-probe)
