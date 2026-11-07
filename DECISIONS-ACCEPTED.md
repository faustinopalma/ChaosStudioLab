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

On 7 November 2026 the operator authorized autonomous implementation, deployment, necessary repairs and testing of a new private AKS/PostgreSQL comparison. Keep the new resource groups active until the operator orders stop or deletion. Orchestrate bounded foreground stages from the PC with visible progress and logs; use one private Ubuntu managed-identity runner for publication and measurement. Preserve ownership checks, unrelated resources and every acknowledged write.

Choose **AKS Standard without Node Auto Provisioning (NAP)**. Chaos Studio guidance supports the node VM scale-set fault path for this configuration and excludes NAP-enabled clusters. Sweden Central was selected after live qualification found `Standard_D4ds_v5` unrestricted in zones 1, 2 and 3 and PostgreSQL zone-redundant HA enabled; the initial Italy North VM candidate was restricted. Kubernetes 1.35.9 was checked in the supported catalog. Catalog qualification remains distinct from successful provisioning and baseline acceptance.

The design uses a private API server with public FQDN disabled, Azure CNI Overlay with Cilium, private application HTTPS through an internal load balancer, a private Premium container registry with managed-identity build/pull access, private Key Vault and private PostgreSQL 16 with Entra-only authentication and zone-redundant HA (intended primary zone 1, standby zone 2). The initial AKS lab omits AMPLS and Log Analytics. Preserve application logs through the private Kubernetes API and evidence from the runner's independent observer and node-topology monitor; keep all raw evidence under ignored `.local\`. Additional observability services require an actual need.

Use three dedicated tainted system nodes across three zones and six user pools, each containing one node: two user nodes per zone, nine nodes total. Six baseline application pods must participate across the six user nodes and three physical zones. Keep node counts static and disable autoscaling and NAP. Surviving capacity may reschedule pods; record AKS reconciliation and remediation.

The selected live native node-shutdown Action exposes `GracefulShutdown` and `Zones`, with no instance-ID selector. Exact-node targeting therefore uses a verified single-node user-pool VMSS. Zone-compute targeting selects exactly three owned VMSS: the system pool and the two zone-1 user pools, logically labeled z1a and z1b, with `Zones=['1']`. The selector includes only the zone-1 system VM and the two user nodes; omit the other four user pools to avoid empty-zone matches. Define shutdown duration as `PT7M` so independent samples can demonstrate at least 300 continuous seconds physically off despite provider startup/restoration overhead. Require independently observed VM power states and Kubernetes NotReady evidence, plus healthy surviving pods. Replacement or restart that shortens the required sustained window fails that gate.

Give the independent runner Reader access to the owned AKS node resource group for power-state evidence. Give the Chaos identity Virtual Machine Contributor and Reader at that node-group boundary for native shutdown and resource reads. These roles have separate mutation/observation purposes; verify effective authorization and actual callers without granting the observer compute mutation rights.

The workload readiness probe checks process liveness, keeping application endpoints routable during transient database dependency failure. Keep explicit `/health/ready` as the baseline and restored-health qualification gate, alongside independent business/canary evidence. A Kubernetes Ready pod alone does not establish database-dependent service health. Database/combined recovery uses the approved 180-second objective, a complete 60-second qualifying window at 99% business/canary success and successful-operation p95 at most one second, and 300 continuous stable seconds at 99.9% business success and baseline latency.

Run baseline, exact-node shutdown, zone-compute shutdown, PostgreSQL forced failover and database-first combined overlap tests. Keep process/pod faults separately attributed. HA-AZ-001 remains BLOCKED until a supported physical full-zone injection and independent effect evidence exist. Report full-phase availability separately from recovery and complete-history checksum retention. The [AKS plan](docs/aks-lab.md), [limits](docs/experiment-limits.md) and [results register](docs/aks-results.md) define publication boundaries; no AKS PASS is implied by this decision.
