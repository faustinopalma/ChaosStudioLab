# Accepted design decisions

**Current decisions: D17-D19, D21 and D22.** The [specification](docs/specification.md) and [implementation contracts](docs/implementation-contracts.md) describe the active private App Service/native Chaos laboratory. Earlier Container Apps/controller decisions are recoverable from Git tag `baseline-before-app-service-refactor`.

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
