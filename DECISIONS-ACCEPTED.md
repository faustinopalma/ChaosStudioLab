# Accepted design decisions

**Current comparison decision: D24.** D17-D23 record the App Service architecture, operating authorization and Windows comparison. Those dedicated groups were deleted by the operator on 6 November 2026; their measured outcomes remain in the [App Service results](docs/app-service-results.md). The [lab guide](docs/lab-guide.md) connects that history to the new private AKS/PostgreSQL laboratory. Earlier Container Apps/controller decisions are recoverable from Git tag `baseline-before-app-service-refactor`.

## D17. Private Azure App Service across three zones

Linux is the operator-selected baseline. One dedicated Premium plan provides six workers, `zoneRedundant=true`, `maximumNumberOfZones>=3` and `perSiteScaling=false`. Read the actual application instance inventory and join each of its six IDs to health and authenticated business traffic across three observed physical zones.

Use outbound VNet Integration and inbound Private Endpoint on separate subnets, private application/SCM DNS and disabled public application data-plane access. Retain private PostgreSQL zone-redundant HA, distinct Healthy primary/standby zones, the proven management topology and one private runner.

Source and deployment now use App Service. Container Apps, its registry/image path, Automation Account, Hybrid Workers and lifecycle control storage are retired. Historical Container Apps measurements retain their original platform attribution.

## D18. Local deployment and operator-managed deletion

Orchestrate from the PC with visible logs and bounded stages. The single private runner performs private publication, migrations and measurements. Each attributable load run has a deadline and independent observation.

The operator has requested deployment, necessary repairs and the complete deterministic suite. The final environment remains available for subsequent operator teardown. Save actual inventory, deletion dependencies and retained-object limitations in the private report. Provisioning, troubleshooting and measurement durations are recorded separately.

## D19. Modern native Chaos and bounded evidence

Use modern Workspaces, Scenarios and native Actions with a verified regional preview contract. Test exact-instance process crash, verified zone-selected process crash, PostgreSQL forced failover and independently evidenced combined overlap.

Qualify runtime/OS/selector support against the actual target. Report unsupported required coverage as BLOCKED with the exact provider or documented evidence. The [Windows comparison](docs/research.md#linux-baseline-and-windows-test-coverage) records the specific Windows-only template advantage and separates it from individual Action eligibility.

Process crashes are discrete effects. HA-AZ-001 requires supported genuine correlated infrastructure-zone loss. Each test has its own availability, recovery and complete-history write-retention verdict; complete-suite PASS requires all mandatory coverage.

## D20. Initial regional preference

The initial preference was Italy North, then Sweden Central. Subsequent expanded authorization in D21 replaced that preference as a selection constraint. Original allocation/provider responses remain in ignored evidence.

## D21. Expanded regional qualification and cross-region Workspaces

The operator authorized any available region until the laboratory succeeds. Live subscription-specific service eligibility and exact six-worker AZ allocation validation determine selection.

Microsoft documents that a [Workspace can run Scenarios against resources in any Azure region](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-region-availability#regional-availability-of-chaos-studio-workspaces), independently of Workspace placement.

The current workload is Spain Central / P1v3, with six participating Linux workers across three observed physical zones and private PostgreSQL HA. The single runner, operations VNet/NAT/Bastion and Workspace use Sweden Central with global VNet peering. Existing group metadata and ownership remain unchanged.

## D22. Autonomous completion and withdrawn operational prohibitions

On 5 November 2026 the operator withdrew all previous project-level operational prohibitions and requested autonomous completion without a cost ceiling. Existing database start, necessary lab repairs, policy-exemption maintenance, regional alternatives and the complete requested tests are authorized directly.

Active source/docs/configuration use this authorization. Obsolete prohibition-only entrypoints and regional allowlists are removed. Actual Azure authentication, authorization, policy responses, ownership, platform capability, private connectivity and measurable acceptance are verified during execution. Historical results and stopped-database guards retain their evidence meaning.

## D23. Explicit Windows comparison variant for native process crash

On 6 November 2026 the operator directed that the complete App Service HA suite be made to work, including new deployments where needed. Linux App Service process deletion failed on every tested stack. Where process listing worked (.NET 8, .NET 9 and Node.js 22), deletion returned HTTP 400 `This runtime stack is not yet supported on Linux`. .NET 10 and 11 listing returned 409 (dotnet-monitor), Python 3.13, Java 21 and container listing returned 400, and Node.js 24 listed no processes. Required application and combined coverage therefore cannot run on Linux.

The suite therefore runs on a Windows App Service comparison variant beside the retained Linux deployment. The variant keeps the same requirements: six workers in a zone-redundant Premium plan across three observed physical zones, Private Endpoint ingress, VNet Integration egress, private SCM publication, disabled public access, the same private PostgreSQL HA server, the modern Workspace and native Actions. Windows native validation rejects an explicit `processName`, so the Windows Scenarios omit it. The measured default target under out-of-process hosting is the dotnet application worker.

Linux results remain reported separately with their BLOCKED application verdicts. Windows results establish the Windows variant only and make no claim about Linux support. HA-AZ-001 remains a separate guard requiring genuine correlated infrastructure-zone evidence.

## D24. Private AKS comparative architecture and operator authorization

On 7 November 2026 the operator authorized autonomous implementation, deployment, necessary repairs and testing of a new private AKS/PostgreSQL comparison. The later instruction authorizes teardown of the experiment's owned resources after successful native tests, superseding the initial leave-running instruction. Orchestrate bounded foreground stages from the PC with visible progress and logs; use one private Ubuntu managed-identity runner for publication and measurement. Preserve ownership checks, unrelated resources and every acknowledged write.

Choose **AKS Standard without Node Auto Provisioning (NAP)**. Chaos Studio guidance supports the node VM scale-set fault path for this configuration and excludes NAP-enabled clusters. Sweden Central was selected after live qualification found `Standard_D4ds_v5` unrestricted in zones 1, 2 and 3 and PostgreSQL zone-redundant HA enabled; the initial Italy North VM candidate was restricted. Kubernetes 1.35.9 was checked in the supported catalog. Catalog qualification remains distinct from successful provisioning and baseline acceptance.

Live qualification on 7 November at about 10:42 UTC verified AKS 1.35.9 on Azure Linux 3.0, nine Ready nodes across seven VMSS and six .NET 10 pods, one per user node across three zones. Private HTTPS/authentication/idempotence/checksum smoke checks and native Workspace discovery/non-fault exact-node, zone and database validations passed. BASE-001 subsequently passed at about 11:03 UTC with 100% business success and successful-operation p95 11 ms. The original HA-NODE-001 then failed its first-five-minute availability gate at 98.75%, despite sustained node loss and retained writes. Preserve that original FAIL in the [results register](docs/aks-results.md).

The workload design uses a private API server with public FQDN disabled, Azure CNI Overlay with Cilium, private application HTTPS through an internal load balancer, a private Premium container registry with managed-identity build/pull access, private Key Vault and private PostgreSQL 16 with Entra-only authentication and zone-redundant HA (intended primary zone 1, standby zone 2). The initial lab templates intentionally omit AMPLS and application Log Analytics deployment. Application logs use the private Kubernetes API and independent runner observations; raw business measurement evidence remains under ignored `.local\`.

Read-only live scope checks nevertheless found AKS Defender security monitoring/gating enabled and referencing an extra default regional Log Analytics workspace with public ingestion/query enabled. That workspace was created at 10:56:57 UTC in a pre-existing group outside the four owned lab groups. Correlated Started/Accepted/Succeeded Activity Log writes independently authenticate the subscription's Defender for Containers managed identity; the actual AKS Defender profile references the created workspace. Governance-managed creation is proven, with exact identifiers/claims retained privately. Original 24 unrelated IDs/complete returned metadata are unchanged; inventory is 25 and the hard delta guard remains FAIL.

No PC command explicitly created, modified or deleted that workspace/group or changed governance for this finding. Proven managed attribution does not make the resource manifest-owned. Leave it untouched for operator review; do not weaken the guard, automatically delete it, disable governance or renew an exemption. Private application/API/PG/ACR/KV paths remain qualified. All-security-telemetry privacy is not established.

Use three dedicated tainted system nodes across three zones and six user pools, each containing one node: two user nodes per zone, nine nodes total. Six baseline application pods must participate across six distinct user nodes and three physical zones. Keep node counts static and disable autoscaling and NAP. Record AKS reconciliation and remediation.

The current architectural repair also qualifies a shared private HA confirmed-order read cache in Azure Managed Redis. Local cache admission stays bounded and predictable; the shared layer serves SQL-confirmed immutable rows to cold workers during PostgreSQL failover. Reuse the runtime Workload Identity, private-endpoint subnet and private DNS links; disable public/cache-key authentication and require verified TLS. Every write/replay still reaches SQL, dependency probes remain uncached and direct SQL snapshots establish retention. Managed Redis remains a distinct regional dependency outside selected-AKS-node fault targets; preserve that coverage limit and every earlier failed case. See the [repair design](docs/aks-lab.md#immutable-read-cache-and-ingress-protocol-repair) and [results](docs/aks-results.md).

The original node case restored nine Ready nodes and six Ready pods automatically, but left two pods on z1b and none on the returned z1a: only five distinct application workers. Correct the scheduling configuration with hard pod anti-affinity on `kubernetes.io/hostname`. Require one application pod per user node and automatic restoration of six-worker baseline placement. With one or two user nodes off, five or four application pods should serve; missing replicas remain Pending until their nodes return instead of co-locating on survivors.

Correct private Service routing with `externalTrafficPolicy: Local` and supported five-second/two-probe load-balancer health annotations. Node-local endpoint health should couple backend eligibility to local serving capacity and node power, reducing the original Cluster policy's cross-node stale-endpoint routing exposure. Effective health-probe behavior and withdrawal timing still need live verification; the annotation values supply no guarantee of the five-second complete-outage objective.

The correction was applied after the original measurement and qualified at 11:46:14 UTC, taking 67.7708 s for apply/rollout/qualification. Private IP, TLS, pinned image/business revision, six replicas, six user pools, three physical zones and all thresholds remained unchanged. Actual ILB HTTP `/healthz` node-port probing qualified at five seconds, `numberOfProbes=2` and `probeThreshold=2`; all six workers and three zones passed per-pod health/checksum traffic. Fresh corrected BASE-001 passed. The corrected twelve-minute node case then passed first-five-minute service and automatic placement but failed 300-second stability. Preserve this separate FAIL. No manual restart during measurement may obtain recovery or erase earlier outcomes.

Before applying, the correction passed Bicep/private invariants, native contracts, effect fixtures and owned Kubernetes server dry-run/diff. Changes were limited to Deployment anti-affinity, Service Local/five-second/two-probe settings and the server-allocated `healthCheckNodePort`; namespace, service account and PDB remained unchanged. Qualification guards check actual Service and anti-affinity configuration. Preserve dry-run, setup rollout, fresh baseline and fault measurement as separate evidence stages.

The selected live native node-shutdown Action exposes `GracefulShutdown` and `Zones`, with no instance-ID selector. Exact-node targeting therefore uses a verified single-node user-pool VMSS. Zone-compute targeting selects exactly three owned VMSS: the system pool and the two zone-1 user pools, logically labeled z1a and z1b, with `Zones=['1']`. The selector includes only the zone-1 system VM and the two user nodes; omit the other four user pools to avoid empty-zone matches. Define shutdown duration as `PT7M` so independent samples can demonstrate at least 300 continuous seconds physically off despite provider startup/restoration overhead. Require independently observed VM power states and Kubernetes NotReady evidence, plus healthy surviving pods. Replacement or restart that shortens the required sustained window fails that gate.

Give the independent runner Reader access to the owned AKS node resource group for power-state evidence. Give the Chaos identity Virtual Machine Contributor and Reader at that node-group boundary for native shutdown and resource reads. These roles have separate mutation/observation purposes; verify effective authorization and actual callers without granting the observer compute mutation rights.

The initial actual node-shutdown retry completed its native Action and independent caller/object-claim audit. The audit verified the declared Workspace user-assigned managed identity despite inconsistent reported-principal metadata. Preserve that discrepancy and require independent target-operation attribution; native completion and caller identity leave sustained effect, business recovery and retention to their own evidence gates.

Offline independent re-evaluation of that original case passed recovery at 47.434 s into a qualifying 60-second window and passed 300-second stability. Preserve these PASS results alongside first-five-minute availability FAIL and final-placement FAIL; one gate's failure must not mask another gate's measured result.

Retain independent effects before evaluating final layout. Aggregate full-phase SLO failure into overall case FAIL, even when native execution, effect, recovery or retention passes. In particular, a database/combined case with availability FAIL cannot receive overall PASS. Actual-entrypoint AST fixtures exercise PASS/FAIL/INCONCLUSIVE combinations; incomplete evidence supplies no overall success.

The corrected node case's initial analysis INCONCLUSIVE came from an expected unscheduled Pending replacement without `nodeName`. The evaluator now skips only unscheduled Pending pods, rejects unscheduled non-Pending pods, and preserves scheduled-node checks. Re-evaluation of unchanged evidence passed recovery at 0.732 s but failed stability across 362 complete candidate windows. Stable-window FAIL propagates overall FAIL. Analysis repair and a subsequent fresh injection have separate attribution.

Fault load phases use 18 minutes with bounded 20-minute independent observers, allowing a complete 300-second stable period after seven-minute shutdown and restoration. First-five-minute targets, load rate, VU caps and native shutdown duration remain unchanged. The eighteen-minute node case is complete; continue zone/database/combined coverage without architecture/image changes or resetting the qualified baseline.

The eighteen-minute node case completed FAIL: exact first-five-minute business success was 98.95%, with 63 failures among 6,000 versus the unchanged maximum 60. Native/audit, sustained shutdown 306.1511 s, recovery 39.181 s, 300-second stability, six-worker restoration and all-history retention passed independently. The longer horizon fixed missing stability coverage, while availability still missed its target. Do not repeatedly resubmit faults until a PASS or recast this measured FAIL.

Selected-zone compute shutdown completed FAIL: three selected VMs were independently off for 304.0433 s, six others remained running and traffic came from surviving zones 2/3. Exact first-five-minute business success 97.85% and full-phase success 98.9629630% failed against 99%; native/audit, recovery 64.320 s, stability, placement and retention passed separately. Preserve this overall FAIL alongside all three node outcomes.

Node transport diagnostics recorded 458 business and 51 canary failed attempts, all status 0 with approximately eight-second durations across 12:42–12:52. Root cause remains unproven; distinguish observations from routing/probe hypotheses. Database failover executed/audited successfully, then reconciled to overall FAIL at 98.0093514% full-phase success against 99.9%, including 113 business/20 canary drops. Recovery 28.551 s, stable service and role swap passed separately.

The original database topology observer exited on one ten-second ARM GET timeout. Preserve the interrupted trace and initial pipeline FAIL. Unchanged load/health/topology evidence and all-history reconciliation were retrieved without another injection; database recovery uses the complete independent dependency observer and actual role inventory, without claiming complete topology coverage.

Future known transient ARM timeouts/429/5xx are explicitly diagnosed, the entire incomplete sample is discarded, and observation continues within existing bounds. The maximum permitted gap remains 30 seconds; unauthorized errors remain fatal. Retrieve load/retention evidence before reporting observer failure. Actual catch-handling fixtures passed; repairs do not erase the prior observer interruption.

Combined completed overall FAIL at 97.4445628% full-phase success against 99.9%, including 118 business/20 canary drops. Both native operations/authenticated identities, observers, effect, independent overlap, recovery 28.855 s, stability, retention and final placement passed. Actual power-off was bracketed by database 503 observations without an intervening healthy sample; submission timing alone was not used as proof.

Final private qualification passed nine Ready Linux nodes, six distinct user workers across three physical zones and Healthy zone-redundant PostgreSQL (primary 1, standby 2). Complete-history retention verified 37,659 acknowledged writes/ten runs with zero loss/checksum mismatch. HA-AZ-001 remains BLOCKED; its explicit guard exits 1 without injecting or changing Azure.

Final owned inventory contains 87 resource/definition/exemption IDs across network 17, workload 42, operations 11 and managed nodes 17. All four groups remain active. On an explicit operator deletion order, remove owned workload/AKS first, allow AKS to delete its managed node group and verify absence, then operations and network. Never delete the pre-existing default regional group or its Defender-managed workspace. The external scope delta guard remains FAIL and is not waived by successful private qualification.

Manifest/handoff and ignored `.local\<run>\OPERATOR-RESULTS.md` persist final FAIL, health PASS and all 37,659 retained writes, including exact private inventory/access instructions. Only the temporary PC tunnel helper was stopped; Azure lab resources remain running/active. Source guard/research checkpoint `fae2d0f` passed fixtures and verified the HA-AZ-001 exit-1 guard; no automatic deletion follows that checkpoint.

The ownership guard compares other-project resource identifiers and metadata order-independently, persists evidence after diagnosis, and rejects changed tags. Fixtures accept tag reordering and reject changed tag values. Keep these safety invariants separate from measured service verdicts.

The workload readiness probe checks process liveness, keeping application endpoints routable during transient database dependency failure. Keep explicit `/health/ready` as the baseline and restored-health qualification gate, alongside independent business/canary evidence. A Kubernetes Ready pod alone does not establish database-dependent service health. Database/combined recovery uses the approved 180-second objective, a complete 60-second qualifying window at 99% business/canary success and successful-operation p95 at most one second, and 300 continuous stable seconds at 99.9% business success and baseline latency.

Run baseline, exact-node shutdown, zone-compute shutdown, PostgreSQL forced failover and database-first combined overlap tests. Keep process/pod faults separately attributed. HA-AZ-001 remains BLOCKED until a supported physical full-zone injection and independent effect evidence exist. Report full-phase availability separately from recovery and complete-history checksum retention. The [AKS plan](docs/aks-lab.md), [limits](docs/experiment-limits.md) and [results register](docs/aks-results.md) define publication boundaries; no AKS PASS is implied by this decision.
