# Azure Chaos Studio resilience lab

An order API commits a write to PostgreSQL and acknowledges it to the client. If an application process, compute node or database primary then fails, can clients continue working, how quickly does service recover, and does every acknowledged write remain available?

This lab uses Azure Chaos Studio to investigate those questions on Azure App Service and Azure Kubernetes Service (AKS). Its objective covers *high availability (HA)*, continued service and automatic recovery through failures, and *disaster recovery (DR)*, restoring service and data after a broader disaster. The recorded experiments provide component-level HA evidence; regional failover and backup restoration remain unvalidated.

Start with the [executive summary](docs/executive-summary.md) for both architecture diagrams, attempted tests, successful mechanisms and remaining evidence gaps.

## Reading route

1. [Executive summary](docs/executive-summary.md): architecture comparison, outcomes and HA/DR conclusions.
2. [Lab guide](docs/lab-guide.md): document roles, evidence questions and historical context.
3. [App Service results](docs/app-service-results.md): Windows process-crash and database tests, followed by earlier Linux attempts.
4. [AKS results](docs/aks-results.md#final-bounded-close-summary----7-november-2026): final closure first, then the original failures and successive repairs.
5. [Experiment limits](docs/experiment-limits.md): acceptance thresholds, fault coverage and observation gaps.
6. [AKS architecture and test contracts](docs/aks-lab.md): topology, caching, native targets and operating procedures.
7. [Technical references](docs/lab-guide.md#technical-reference): specifications, accepted decisions and optional Container Apps archives.

## Two architectures, one measurement model

Both designs run the order API behind private ingress and use private, zone-redundant PostgreSQL. Their hosting and compute-fault boundaries differ:

| Area | App Service | AKS |
| --- | --- | --- |
| Workload region | Spain Central | Sweden Central |
| Application placement | Six managed workers, observed as two per physical zone | Six pods on six distinct user nodes, plus three system nodes across three zones |
| Private ingress | Application Private Endpoint; separate outbound VNet Integration | Internal load balancer with node health probes and Local routing |
| Database and cache | PostgreSQL primary/standby in different zones | PostgreSQL HA; final repair adds local and private shared confirmed-order caching |
| Injected compute effect | Application-process crashes on selected workers | Sustained shutdown of an exact node or the three owned nodes in the selected zone |
| Architecture drawing | [App Service](docs/diagrams/04-private-linux-app-service.svg) | [AKS](docs/diagrams/06-private-aks-zone-lab.svg) |

A private runner generates business load, records acknowledgements and observes actual fault effects. Native Action completion, business availability, recovery time and retained writes receive separate verdicts. The [diagram index](docs/diagrams/README.md) distinguishes these architectures from the earlier Container Apps design.

## Current status — 7 November 2026

Measurements are closed. The results below belong to specific tested versions; the final AKS version has an incomplete suite.

| Experiment | Recorded conclusion |
| --- | --- |
| Windows App Service process crashes | PASS for an exact worker and both workers in one zone, with zero failed business operations |
| Linux App Service process crashes | BLOCKED: native process deletion was unsupported on the tested stacks |
| AKS node and selected-zone compute shutdown | Original cases failed required gates; the first cache/HTTP/1.1 repair passed both cases on that version |
| PostgreSQL failover | Automatic recovery and retention passed in measured cases, while several runs failed full-phase availability |
| Final AKS database test | All 21,600 scheduled business operations succeeded, with zero business drops; overall INCONCLUSIVE because the topology observer stopped early. Twenty-two canary schedules were dropped |
| Combined application/compute and database faults | App Service recovered with failed full-phase availability; original AKS also failed availability. The repaired AKS combined case was not executed |
| Physical whole-zone disaster and regional DR | Whole-zone injection remained BLOCKED; regional failover and backup restoration were not exercised |

The earlier repaired AKS node and selected-zone PASS results were not rerun on the final shared-cache image. They therefore leave the complete final-version suite INCOMPLETE. The [versioned comparison](docs/executive-summary.md#aks-outcomes-and-version-boundaries) keeps these results separate.

Reconciliation retained all 92,616 acknowledged App Service measurement writes across 31 runs and all 78,142 AKS measurement writes across 21 runs. Final AKS direct SQL verification also retained 23 private-journal acknowledgements. These are separate histories; the AKS check bypassed both caches and compared stored checksum values with client acknowledgements.

## What these experiments establish

Chaos Studio supplied useful, scoped tests of process replacement, surviving compute capacity and database promotion. Independent observations exposed real availability failures even when recovery and retained-write checks passed.

The injected effects cover specific components. Restarting processes in one zone leaves the zone's infrastructure available; shutting down owned AKS nodes leaves regional managed dependencies running. A DR conclusion needs a recovery design and measurements for the intended disaster and restore or failover path. The [experiment limits](docs/experiment-limits.md) explain each boundary.

## Repository layout

The implementation and evidence are organized by responsibility:

| Path | Contents |
| --- | --- |
| [docs](docs/) | Executive summary, architecture diagrams, measured results, interpretation and historical reports |
| [infra](infra/) | Bicep templates for private infrastructure and native Chaos scenarios |
| [scripts](scripts/) | Deployment stages, private-runner orchestration, qualification and evidence collection |
| [src](src/) | Order API, PostgreSQL access, confirmed-order caching and API unit tests |
| [tests](tests/) | Contract checks, publication safeguards, load scenarios and result evaluators |
| [config](config/) | Generic lab settings and an environment example with empty private identifiers |

[Accepted decisions](DECISIONS-ACCEPTED.md) record the approved design changes. The earlier Container Apps implementation is preserved at Git tag `baseline-before-app-service-refactor`, with its own [execution history](docs/first-cycle-results.md).

## Reproducing or adapting the lab

Deployment and fault scripts change Azure resources and incur costs. Begin with the [AKS architecture and operating contracts](docs/aks-lab.md) or the [App Service implementation contracts](docs/implementation-contracts.md), then qualify the selected region, supported runtime, permissions, private connectivity and owned resource scope before running a fresh baseline.

The published results describe completed experiments. App Service group deletion was verified on 6 November; AKS teardown became operator-managed and completion was not verified. An AKS governance-managed Log Analytics workspace outside lab ownership had public ingestion/query enabled, leaving the external-scope safeguard FAIL. See [scope limits](docs/experiment-limits.md#managed-security-telemetry-and-external-scope-delta) and the [cleanup order](docs/aks-lab.md#operator-managed-cleanup-order) before reusing operational instructions.

## Publication and private context

Tenant/subscription identifiers, accounts, deployed resource names, credentials, ownership manifests and raw evidence belong in ignored `.local\` and `.azure\` paths. The [environment example](config/environment.example.json) contains empty private identifiers; supply the actual values through the lab's private configuration.

From the repository root, run the publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

The guard checks excluded paths and known private values. Select the relevant ignored environment and private-value registry through `-PrivateConfigurationPath` and `-PrivateValuesPath` when the defaults belong to another lab. Publication also requires secret scanning of the Git history being pushed, because ignore rules leave previously committed content in that history and have no effect on full-folder archives.
