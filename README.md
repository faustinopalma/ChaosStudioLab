# Azure Chaos Studio resilience lab

An order API commits each write to PostgreSQL before acknowledging it. When application replicas, a compute node or the database primary fail, do clients keep working, how quickly does service recover, and does every acknowledged write survive?

This laboratory explored those questions on Azure Container Apps, Azure Kubernetes Service (AKS) and Azure App Service. Azure Chaos Studio injected the faults and an independent private runner measured the effect under constant load. All three environments used private networking and zone-redundant PostgreSQL.

> **Scope.** These results come from a single laboratory exercise run in November 2026: one application, one load profile of 20 operations per second, and specific regions and configurations. They describe how this design behaved under these faults. Results elsewhere depend on application design, configuration and load; Azure availability commitments are defined in the [Azure SLAs](https://aka.ms/CSLA).

## Key findings

- **Capacity loss was absorbed on all three platforms.** In their final configurations, losing two of six Container Apps replicas, one AKS node, all lab nodes in one zone, or the application process on App Service workers cost at most 11 business operations per fault phase of 14,400 to 21,600.
- **Application design determined what clients saw during a database failover.** Service recovered 27–36 seconds after each PostgreSQL zone-redundant failover. With a shared cache of confirmed reads, no business operation failed; without it, 97.3% completed and the errors were concentrated in the role change.
- **No acknowledged write was lost.** Reconciliation after the runs found all 111,358 acknowledged writes with their expected checksums.

## Reading order

1. [Executive summary](docs/executive-summary.md): architectures, results and conclusions.
2. [Method](docs/method.md): workload, fault mechanisms and metrics.
3. Platform results: [Container Apps](docs/container-apps-results.md), [AKS](docs/aks-results.md), [App Service](docs/app-service-results.md).
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

Tenant and subscription IDs, accounts, resource names, credentials and raw evidence stay in the ignored `.local\` and `.azure\` folders; `pwsh .\tests\Test-Publication.ps1` checks this before each commit.
