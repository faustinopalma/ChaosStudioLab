# Azure Chaos Studio resilience lab

The current target is a **private Azure App Service application running across three observed availability zones**, backed by private Azure Database for PostgreSQL Flexible Server with zone-redundant HA.

**Implementation status:** the source still implements the earlier Container Apps laboratory. The App Service source refactor and fresh deployment have not started. Read the current specification before using the existing deployment scripts.

## Required architecture

- Windows App Service Web App and compatible zone-redundant Premium plan, initially using six workers.
- Three-zone readiness requires the actual plan's `maximumNumberOfZones >= 3` and healthy application-instance/traffic evidence from three distinct observed `physicalZone` values.
- Inbound App Service Private Endpoint and outbound regional VNet Integration, using separate subnets.
- Private DNS for application, SCM/Kudu publication, PostgreSQL and required supporting services; public application/database data-plane access disabled.
- Retained PostgreSQL HA with primary and standby in distinct zones.
- One private runner for publication, database bootstrap, migration and optional measurement; retain the proven management connectivity initially.
- Deployment orchestration from the PC with visible progress and local logs. Tests start explicitly; the operator manually deletes the dedicated groups.
- Modern Chaos Studio **Workspaces, Scenarios and Actions**, using native App Service process-crash and PostgreSQL failover Actions after their exact regional contracts are verified.

The refactor removes Container Apps, its Dedicated workload profile/image-pull path, Automation Account, two Hybrid Workers, lifecycle control storage and automatic suspension/deletion. The new design has no independent expiry enforcement when the PC disconnects.

Zone-selected process crashes and a correlated infrastructure-zone outage require separate evidence and verdicts. The earlier database recovery measurement supplies no App Service or three-zone application qualification.

## Current documents

- [Implementation specification](docs/specification.md): authoritative requirements, three-zone acceptance, private paths, native faults and local/manual workflow.
- [Accepted decisions D17-D19](DECISIONS-ACCEPTED.md#d17-private-azure-app-service-across-three-zones): controlling corrections to the previous design.
- [Development readiness](docs/development-readiness.md): defined contracts and pending App Service implementation/qualification.
- [Platform research](docs/research.md#current-app-service-facts-three-zone-and-native-fault-gates): official App Service placement and modern Chaos references.
- [Historical execution results](docs/first-cycle-results.md): measured Container Apps/PostgreSQL results, incomplete application test coverage, troubleshooting and cleanup limitations.

The [earlier architecture guide](docs/architecture-guide.md), [diagrams](docs/diagrams/README.md), [implementation contracts](docs/implementation-contracts.md) and [autonomous cycle method](docs/lab-cycle-method.md) are explicitly marked as historical. Their Container Apps/Automation drawings and commands must be replaced or retired during refactoring.

## Git and private context

Git tag `baseline-before-app-service-refactor` preserves the earlier source and documents. Keep real accounts, tenant/subscription IDs, group names, authentication paths, policy records, manifests, keys and raw evidence in ignored `.local\` and `.azure\` paths. The public environment template is [environment.example.json](config/environment.example.json).

Run the existing publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

Git ignore rules do not protect full-folder archives or erase already-committed data. No remote publication is implied by a local commit.

The earlier groups' final deletion was handed to the operator. This repository records no independently certified final cleanup or purge result for that handoff.
