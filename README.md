# Azure Chaos Studio resilience lab

This repository compares recovery and acknowledged-write durability under controlled Azure application, compute and PostgreSQL faults.

**Start with the [lab guide](docs/lab-guide.md).** It connects the measured App Service experiments, their evidence limits, the new private AKS/PostgreSQL design, and the detailed technical references.

## Current status — 7 November 2026

- **App Service experiments are historical.** The operator deleted their dedicated resource groups on 6 November at 09:43 UTC. Verification found seven unrelated resource groups and their 24 resources unchanged. Historical results and retained evidence remain available.
- **Private AKS/PostgreSQL infrastructure is provisioning.** Scope and identities are deployed; ARM validation passed with 42 Creates and five owned-identity Ignores. The design uses AKS Standard in Sweden Central, three system nodes and six single-node user pools across three zones, private application HTTPS ingress, and private PostgreSQL 16 with zone-redundant HA. Deployment and measured acceptance have separate gates. See the [AKS design and test plan](docs/aks-lab.md).
- **AKS outcomes are pending.** The [AKS results register](docs/aks-results.md) records qualification, execution and acceptance separately. Planned fault coverage supplies no measured resilience verdict.
- **The new lab remains active after execution.** Deployment, necessary repairs and tests are authorized autonomously; resource groups remain available until the operator orders stop or deletion. [D24](DECISIONS-ACCEPTED.md#d24-private-aks-comparative-architecture-and-operator-authorization) records the comparison and operating scope.

## Measured App Service outcomes

The Windows comparison used six private App Service workers across three observed physical zones in Spain Central.

| Experiment | Observed outcome |
| --- | --- |
| BASE-001 | **PASS**: 100% business success; successful-operation p95 123 ms |
| HA-APP-001 | **PASS**: exact-instance dotnet process replacement started 12.7 s after acceptance; zero failed business operations |
| HA-APP-ZONE-001 | **PASS**: both selected-zone workers' dotnet processes replaced in 11–13 s; zero failed business operations |
| HA-DB-001 | Recovery/durability **PASS**, recovery 36.359 s; full-phase availability **FAIL**, 97.347% |
| HA-COMBINED-001 | Recovery/durability/observed overlap **PASS**, recovery 34.989 s; full-phase availability **FAIL**, 97.324% |
| HA-AZ-001 | **BLOCKED**: no qualifying sustained physical full-zone outage was injected |

Complete-history reconciliation retained **92,616 of 92,616 acknowledged measurement writes across 31 Linux and Windows runs**, with matching checksums. Linux process deletion returned HTTP 400 `This runtime stack is not yet supported on Linux` wherever listing worked (.NET 8, .NET 9 and Node.js 22); other stacks had listing blockers.

Read the [original App Service results](docs/app-service-results.md) for phase metrics and execution history, and [experiment limits](docs/experiment-limits.md) for the scope of each conclusion. The historical .NET 9 App Service stacks reach their recorded support deadline on 10 November 2026; the AKS comparison plans a supported .NET 10 container using the existing application source.

## Reading route

1. [Lab guide](docs/lab-guide.md) — one navigable entry point.
2. [App Service execution results](docs/app-service-results.md) and [experiment limits](docs/experiment-limits.md) — measured behavior and boundaries.
3. [Private AKS lab](docs/aks-lab.md) — architecture, native node-shutdown targeting and acceptance.
4. [AKS results](docs/aks-results.md) — pending results and the evidence needed to publish verdicts.
5. [Accepted decisions](DECISIONS-ACCEPTED.md) and the guide's [technical-reference index](docs/lab-guide.md#technical-reference) — detailed contracts and historical material.

## Publication and private context

Keep accounts, tenant/subscription identifiers, resource-group names, authentication paths, policy records, manifests, credentials and raw evidence in ignored `.local\` and `.azure\` paths. Publish sanitized architecture and results. The [environment example](config/environment.example.json) documents the existing App Service configuration; it does not establish AKS deployment readiness.

Run the publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

Git ignore rules do not protect full-folder archives or remove already-committed data. A local commit implies no remote publication. Resource-group deletion alone does not certify removal of soft-deleted vaults, service backups or audit retention.

Git tag `baseline-before-app-service-refactor` preserves the earlier Container Apps implementation. Its [execution history](docs/first-cycle-results.md) retains its original platform attribution.
