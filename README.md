# Azure Chaos Studio resilience lab

The current target is a **private Linux Azure App Service application running across three observed availability zones**, backed by private Azure Database for PostgreSQL Flexible Server with zone-redundant HA.

**Region policy:** After the operator authorized an expanded search, **Spain Central / P1v3** passed six-worker Linux zone-redundant ARM validation and PostgreSQL HA eligibility. Keep the modern **Chaos Workspace in Sweden Central**, whose documented targeting supports resources in other regions. [D21](DECISIONS-ACCEPTED.md#d21-expanded-regional-qualification-and-cross-region-workspaces) records the selection. Reuse the current groups/ownership/profile; their group metadata remains Sweden Central. Actual plan, application placement/private paths and native tests require separate live qualification.

**Implementation status:** the private Linux App Service/single-runner source topology compiles and its targeted local regressions pass. The three dedicated groups and narrowly scoped, finite public-IP policy exemption were created after operator approval. The previous Sweden Central allocation attempts failed with zero AZ-worker quota; the newly selected Spain Central candidate requires exact-source validation/preview and actual-plan qualification before dependent provisioning. Private SCM, actual three-zone participation and native fault execution remain unqualified.

The [foreground App Service preflight](scripts/Test-AppServicePreflight.ps1) is available for a new run's read-only qualification. Supply the approved `CSL_ENVIRONMENT_FILE`, a fresh `-StateDirectory` under ignored `.local` and `-PreviousManifestPath`. It preserves raw evidence and a new ownership manifest, enforces per-command deadlines and reports every requested test separately. It never deploys, executes faults or cleans up. Resume an existing live run with its current manifest; do not generate another ownership GUID or recreate its groups. See [current research](docs/research.md#fresh-foreground-catalog-qualification).

[Build-Lab.ps1](scripts/Build-Lab.ps1) stages the early plan before identities/dependencies, a single foreground runner and checksummed package publication through private SCM. Its stage-specific validation guard currently prevents further provisioning. The previous unattended cycle, controller, Suspend/Resume and Destroy entrypoints fail immediately. [Test-Lab.ps1](scripts/Test-Lab.ps1) also fails explicitly until the native execution/effect evaluator is implemented and qualified; none of the six requested tests has passed in the App Service run.

## Required architecture

- Linux App Service Web App and compatible zone-redundant Premium plan, initially using six workers.
- Three-zone readiness requires the actual plan's `maximumNumberOfZones >= 3` and healthy application-instance/traffic evidence from three distinct observed `physicalZone` values.
- Inbound App Service Private Endpoint and outbound regional VNet Integration, using separate subnets.
- Private DNS for application, SCM/Kudu publication, PostgreSQL and required supporting services; public application/database data-plane access disabled.
- Retained PostgreSQL HA with primary and standby in distinct zones.
- One private runner for publication, database bootstrap, migration and optional measurement; retain the proven management connectivity initially.
- Deployment orchestration from the PC with visible progress and local logs. Tests start explicitly; the operator manually deletes the dedicated groups.
- Modern Chaos Studio **Workspaces, Scenarios and Actions**, using native App Service process-crash and PostgreSQL failover Actions after their exact regional contracts are verified.

The refactor removes Container Apps, its Dedicated workload profile/image-pull path, Automation Account, two Hybrid Workers, lifecycle control storage and automatic suspension/deletion. The new design has no independent expiry enforcement when the PC disconnects.

Zone-selected process crashes and a correlated infrastructure-zone outage require separate evidence and verdicts. The earlier database recovery measurement supplies no App Service or three-zone application qualification.

Linux is the selected baseline. Qualify native Action support on Linux and record unsupported tests explicitly. The [OS compatibility comparison](docs/research.md#linux-baseline-and-windows-test-coverage) distinguishes a documented Windows-only template from unverified Linux Action eligibility. Do not switch to Windows automatically.

## Current documents

- [Implementation specification](docs/specification.md): authoritative requirements, three-zone acceptance, private paths, native faults and local/manual workflow.
- [Accepted decisions D17-D19](DECISIONS-ACCEPTED.md#d17-private-azure-app-service-across-three-zones): controlling corrections to the previous design.
- [Development readiness](docs/development-readiness.md): defined contracts and pending App Service implementation/qualification.
- [Platform research](docs/research.md#current-app-service-facts-three-zone-and-native-fault-gates): official App Service placement and modern Chaos references.
- [Historical execution results](docs/first-cycle-results.md): measured Container Apps/PostgreSQL results, incomplete application test coverage, troubleshooting and cleanup limitations.

The [earlier architecture guide](docs/architecture-guide.md), [implementation contracts](docs/implementation-contracts.md) and [autonomous cycle method](docs/lab-cycle-method.md) remain historical. The [diagram index](docs/diagrams/README.md) separates the current target/evidence diagrams from the historical Container Apps/Automation drawings.

## Git and private context

Git tag `baseline-before-app-service-refactor` preserves the earlier source and documents. Keep real accounts, tenant/subscription IDs, group names, authentication paths, policy records, manifests, keys and raw evidence in ignored `.local\` and `.azure\` paths. The public environment template is [environment.example.json](config/environment.example.json).

Keep session-to-session handoffs and operational progress journals under ignored `.local\handoff\`. Publish architectural requirements and sanitized results separately; operational session state has no public root-level status file.

Run the existing publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

Git ignore rules do not protect full-folder archives or erase already-committed data. No remote publication is implied by a local commit.

Read-only preflight verified that the previous dedicated groups and exact old Container Apps managed group were absent before the new scope was created. Unrelated resources were preserved. A recoverable vault remains under its retention policy; no purge was performed. The new groups remain deployed for operator-managed deletion, and group absence does not certify backup/audit-retention cleanup.
