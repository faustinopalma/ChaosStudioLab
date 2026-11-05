# Azure Chaos Studio resilience lab

The current target is a **private Linux Azure App Service application running across three observed availability zones**, backed by private Azure Database for PostgreSQL Flexible Server with zone-redundant HA.

**Region selection:** The deployed workload uses **Spain Central / P1v3**, with six Linux workers and actual `maximumNumberOfZones: 3`. All six workers served successful health and authenticated checksum-verified business requests across `spaincentral-az1`, `spaincentral-az2` and `spaincentral-az3`. The single private runner/operations VNet/NAT/Bastion and modern **Chaos Workspace remain in Sweden Central**, using global VNet peering and documented cross-region native targeting. [D21](DECISIONS-ACCEPTED.md#d21-expanded-regional-qualification-and-cross-region-workspaces) records the selection. Any region can be configured and live-qualified.

**Current authorization:** [D22](DECISIONS-ACCEPTED.md#d22-autonomous-completion-and-withdrawn-operational-prohibitions) records autonomous completion without a cost ceiling, including the existing database start, necessary lab repairs, exemption maintenance and the full requested tests. Active project-level operational prohibitions and extra restart-approval requirements have been removed.

**Execution status:** private infrastructure, private SCM publication and actual six-worker/three-zone participation are verified. PostgreSQL readiness was restored and complete **BASE-001 passed**: 100% success, zero errors/drops and p95 122 ms during the ten-minute baseline. A real exact-instance native submission failed provider target validation; instance/zone validation also fails through an additional Switzerland North Workspace. The native database case is in progress. Required application/combined coverage remains **BLOCKED**, preventing a complete-suite PASS. See [current execution results](docs/app-service-results.md) for separate verdicts, retention and timings.

The [foreground App Service preflight](scripts/Test-AppServicePreflight.ps1) is available for a new run's read-only qualification. Supply the approved `CSL_ENVIRONMENT_FILE`, a fresh `-StateDirectory` under ignored `.local` and `-PreviousManifestPath`. It preserves raw evidence and a new ownership manifest, enforces per-command deadlines and reports every requested test separately. It never deploys, executes faults or cleans up. Resume an existing live run with its current manifest; do not generate another ownership GUID or recreate its groups. See [current research](docs/research.md#fresh-foreground-catalog-qualification).

[Build-Lab.ps1](scripts/Build-Lab.ps1) stages the early plan, private dependencies, single runner, checksummed private publication and definition-only `NativeScenarios` overlay behind separate validation gates. [Test-Lab.ps1](scripts/Test-Lab.ps1) selects one test, requires healthy private PostgreSQL and a successful baseline before injection, and records explicit per-test verdicts. Native effect/recovery/overlap and complete-history retention logic passes local fixtures; live fault qualification remains pending. Obsolete cycle/controller/lifecycle entrypoints have been removed.

## Required architecture

- Linux App Service Web App and compatible zone-redundant Premium plan, initially using six workers.
- Three-zone readiness requires the actual plan's `maximumNumberOfZones >= 3` and healthy application-instance/traffic evidence from three distinct observed `physicalZone` values.
- Inbound App Service Private Endpoint and outbound regional VNet Integration, using separate subnets.
- Private DNS for application, SCM/Kudu publication, PostgreSQL and required supporting services; public application/database data-plane access disabled.
- Retained PostgreSQL HA with primary and standby in distinct zones.
- One private runner for publication, database bootstrap, migration and optional measurement; retain the proven management connectivity initially.
- Deployment orchestration from the PC with visible progress and local logs, executing the requested suite and leaving the final environment available for subsequent operator teardown.
- Modern Chaos Studio **Workspaces, Scenarios and Actions**, using native App Service process-crash and PostgreSQL failover Actions after their exact regional contracts are verified.

The refactor removes Container Apps, its Dedicated workload profile/image-pull path, Automation Account, two Hybrid Workers, lifecycle control storage and automatic suspension/deletion. The new design has no independent expiry enforcement when the PC disconnects.

Zone-selected process crashes and a correlated infrastructure-zone outage require separate evidence and verdicts. The earlier database recovery measurement supplies no App Service or three-zone application qualification.

Linux is the selected baseline. Qualify native Action support on Linux and record unsupported tests explicitly. The [OS compatibility comparison](docs/research.md#linux-baseline-and-windows-test-coverage) distinguishes a documented Windows-only template from unverified Linux Action eligibility.

## Current documents

- [Implementation specification](docs/specification.md): authoritative requirements, three-zone acceptance, private paths, native faults and local/manual workflow.
- [Accepted decisions D17-D19](DECISIONS-ACCEPTED.md#d17-private-azure-app-service-across-three-zones): controlling corrections to the previous design.
- [Implementation contracts](docs/implementation-contracts.md): current operating authorization, deployed architecture and measurable native-test contracts.
- [Development readiness](docs/development-readiness.md): defined contracts and pending App Service implementation/qualification.
- [App Service execution results](docs/app-service-results.md): deployed capabilities, complete baseline, native provider outcomes, retention and separate suite verdicts.
- [Platform research](docs/research.md#current-app-service-facts-three-zone-and-native-fault-gates): official App Service placement and modern Chaos references.
- [Historical execution results](docs/first-cycle-results.md): measured Container Apps/PostgreSQL results, incomplete application test coverage, troubleshooting and cleanup limitations.

The [earlier architecture guide](docs/architecture-guide.md) and [autonomous cycle method](docs/lab-cycle-method.md) remain historical. The [diagram index](docs/diagrams/README.md) separates the current target/evidence diagrams from the historical Container Apps/Automation drawings.

## Git and private context

Git tag `baseline-before-app-service-refactor` preserves the earlier source and documents. Keep real accounts, tenant/subscription IDs, group names, authentication paths, policy records, manifests, keys and raw evidence in ignored `.local\` and `.azure\` paths. The public environment template is [environment.example.json](config/environment.example.json).

Keep session-to-session handoffs and operational progress journals under ignored `.local\handoff\`. Publish architectural requirements and sanitized results separately; operational session state has no public root-level status file.

Run the existing publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

Git ignore rules do not protect full-folder archives or erase already-committed data. No remote publication is implied by a local commit.

Read-only preflight verified that the previous dedicated groups and exact old Container Apps managed group were absent before the new scope was created. Unrelated resources were preserved. A recoverable vault remains under its retention policy; no purge was performed. The new groups remain deployed for operator-managed deletion, and group absence does not certify backup/audit-retention cleanup.
