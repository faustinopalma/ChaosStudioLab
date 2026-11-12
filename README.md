# Azure Chaos Studio resilience lab

An order API commits a write to PostgreSQL and then acknowledges it. If an application process, a compute node, a third of the replicas or the database primary fails, do clients keep working, how fast does service recover, and does every acknowledged write survive?

This lab answers those questions on Azure App Service, Azure Kubernetes Service (AKS) and Azure Container Apps, with Azure Chaos Studio injecting the faults and an independent private runner measuring the effect. Everything runs on private networks with zone-redundant PostgreSQL.

## Results at a glance

Each platform ran under 20 business operations per second. *Business success* is the share of scheduled operations that completed over the whole fault phase; *recovery* is the time from the first observed database error to the first full minute with at least 99% success.

| Fault | App Service | AKS | Container Apps |
| --- | --- | --- | --- |
| Application capacity loss | 100% | 99.96% (one node) / 99.95% (zone-1 nodes) | 100% |
| PostgreSQL failover | 97.35%, recovery 36 s | 99.76%, recovery 27 s | 100%, recovery 35 s |
| Failover plus capacity loss | 97.32%, recovery 35 s | 97.44%, recovery 29 s (first version) | 100%, recovery 28 s |
| Acknowledged writes lost | 0 of 22,424 | 0 of 68,245 | 0 of 20,689 |

These are high-availability tests of component faults. Disaster recovery, such as a regional failover or a backup restore, was outside the scope.

## Reading order

1. [Executive summary](docs/executive-summary.md): architectures, comparison, what Chaos Studio covers, HA and DR conclusions.
2. [Method](docs/method.md): workload, fault mechanisms and metrics.
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

The detailed execution records written during the experiments are preserved at Git tag `detailed-records-2026-11-10`.

## Private context

Tenant and subscription IDs, accounts, resource names, credentials and raw evidence stay in the ignored `.local\` and `.azure\` folders. Run the publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```
