# Azure Chaos Studio resilience lab

An order API commits a write to PostgreSQL and then acknowledges it. If an application process, a compute node, a third of the replicas or the database primary fails, do clients keep working, how fast does service recover, and does every acknowledged write survive?

This lab answers those questions on Azure App Service, Azure Kubernetes Service (AKS) and Azure Container Apps, with Azure Chaos Studio injecting the faults and an independent private runner measuring the effect. Everything runs on private networks with zone-redundant PostgreSQL.

## Results at a glance

| Fault | App Service | AKS | Container Apps |
| --- | --- | --- | --- |
| Application capacity loss | PASS, 100% | PASS, 99.95–99.96% | PASS, 100% |
| PostgreSQL failover | Recovery 36 s, availability 97.3% (FAIL) | Business 100%, INCONCLUSIVE | PASS, 100%, recovery 35 s |
| Both together | Recovery 35 s, availability 97.3% (FAIL) | Not run on the final version | PASS, 100%, recovery 28 s |
| Whole-zone outage | BLOCKED | BLOCKED | BLOCKED |
| Acknowledged writes lost | 0 of 92,616 | 0 of 78,142 | 0 of 26,264 |

The tests establish high availability for component faults. Disaster recovery, meaning a whole zone or region and a backup restore, was not exercised because Chaos Studio offers no fault that takes down a zone with its managed services.

## Reading order

1. [Executive summary](docs/executive-summary.md): architectures, comparison, what Chaos Studio covers, HA and DR conclusions.
2. [Method](docs/method.md): workload, fault mechanisms, acceptance gates and verdicts.
3. Platform results: [App Service](docs/app-service-results.md), [AKS](docs/aks-results.md), [Container Apps](docs/container-apps-results.md).
4. [Running the lab](docs/running-the-lab.md): prerequisites, stages, local checks and cleanup.

## Repository layout

| Path | Contents |
| --- | --- |
| [docs](docs/) | Summary, method, per-platform results and editable SVG architecture diagrams |
| [infra](infra/) | Bicep for the private networks, platforms, PostgreSQL, caches and Chaos Studio scenarios |
| [scripts](scripts/) | Staged build and test entry points per platform, and the runner-side tools |
| [src](src/) | Order API, PostgreSQL and cache access, replica-fault lease and unit tests |
| [tests](tests/) | Load scenario, evaluators, contract fixtures and the publication guard |
| [config](config/) | Generic lab settings and an environment template without private values |

The detailed execution records written during the experiments, including every failed and repaired attempt, are preserved at Git tag `detailed-records-2026-11-10`.

## Private context

Tenant and subscription IDs, accounts, resource names, credentials and raw evidence stay in the ignored `.local\` and `.azure\` folders. Run the publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```
