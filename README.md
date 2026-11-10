# Azure Chaos Studio resilience lab

This repository compares recovery and acknowledged-write durability under controlled Azure application, compute and PostgreSQL faults.

**Start with the [executive summary](docs/executive-summary.md).** It shows both architectures, compares attempted tests and explains the qualified HA results, failures and remaining DR gaps. The [reading guide](docs/lab-guide.md#read-in-this-order) provides the complete document order.

## Current status — 7 November 2026

- **App Service experiments are historical.** Their dedicated groups were deleted on 6 November at 09:43 UTC; seven unrelated groups and 24 resources were verified unchanged. Original results remain available.
- **AKS measurements are closed.** The first cache/HTTP/1.1 repair passed exact-node and selected-zone compute tests. Those cases were not rerun on the final shared-cache version, and the repaired combined case was not executed.
- **The complete final-version resilience suite remains INCOMPLETE.** The final database phase achieved 100% scheduled business success with zero business drops, but its overall verdict is INCONCLUSIVE because the topology observer stopped early. Twenty-two canary schedules were dropped. Original availability failures remain recorded.
- **Final direct SQL reconciliation retained all 78,142 acknowledged AKS measurement writes across 21 runs**, plus 23 private-verification journal acknowledgements, with matching stored checksums. [Final AKS results](docs/aks-results.md#final-bounded-close-summary----7-november-2026) preserve each version's results and evidence limits.
- **DR remains unvalidated.** Physical whole-zone injection is BLOCKED; regional failover and backup restoration were outside the executed coverage.
- **Scope guard FAIL: one extra governance-managed telemetry resource.** Original 24 unrelated IDs/complete returned metadata are unchanged; inventory is 25 after a default regional Log Analytics workspace appeared at 10:56:57 UTC outside the four owned groups. Correlated Activity Log writes independently prove creation by the subscription's Defender for Containers managed identity, and AKS Defender references it. Public ingestion/query are Enabled. The external group remains untouched for operator review; qualified private workload paths do not establish all-security-telemetry privacy.
- **AKS teardown is operator-managed.** A workload-group deletion request was accepted before handoff; completion and subsequent operator deletions were not verified. [D24](DECISIONS-ACCEPTED.md#d24-private-aks-comparative-architecture-and-operator-authorization) records the comparison and operating scope.

Resource-state statements below belong to their dated measurement checkpoints. Private operator reports, exact group names/inventory and raw evidence remain under ignored `.local\` paths.

## Original AKS outcomes

This table preserves the original architecture's failures. The [executive summary's versioned comparison](docs/executive-summary.md#aks-outcomes-and-version-boundaries) also covers the later compute PASS results and final database INCONCLUSIVE.

| Test | Overall verdict and required failure |
| --- | --- |
| BASE-001, original and corrected | **PASS**: 100% business success, baseline p95 11 ms |
| HA-NODE-001, final 18 min | **FAIL**: first-five-minute success 98.95%; recovery 39.181 s, stability and retention PASS |
| HA-ZONE-COMPUTE-001 | **FAIL**: first-five-minute 97.85%, full-phase 98.9629630%; recovery 64.320 s and retention PASS |
| HA-DB-001, reconciled | **FAIL**: full-phase 98.0093514% against 99.9%; recovery 28.551 s and retention PASS; interrupted topology trace preserved |
| HA-COMBINED-001 | **FAIL**: full-phase 97.4445628% against 99.9%; independently observed overlap, recovery 28.855 s, stability and retention PASS |
| HA-AZ-001 | **BLOCKED**: no physical full-zone injection; final guard exits 1 without Azure changes |

For the original series, manifest-to-verification elapsed time was **5 h 05 min 36.744 s**. Ten unique k6 measurement intervals totalled **2 h 07 min 57.297 s**; these are different accounting categories and exclude later repair stages. See [timing attribution](docs/aks-results.md#elapsed-time-and-attribution), [final closure](docs/aks-results.md#timing-and-closure) and [operator-managed cleanup order](docs/aks-lab.md#operator-managed-cleanup-order).

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

Read the [original App Service results](docs/app-service-results.md) for phase metrics and execution history, and [experiment limits](docs/experiment-limits.md) for the scope of each conclusion. The historical .NET 9 App Service stacks reach their recorded support deadline on 10 November 2026; the AKS comparison ran a supported .NET 10 container using the existing application source.

## Reading route

1. [Executive summary](docs/executive-summary.md) — architectures, HA/DR conclusions and useful test coverage.
2. [Lab guide](docs/lab-guide.md) — document roles and reading order.
3. [App Service execution results](docs/app-service-results.md) — the managed-platform experiments.
4. [AKS results](docs/aks-results.md#final-bounded-close-summary----7-november-2026) — final closure first, then original and repair history.
5. [Experiment limits](docs/experiment-limits.md) — evidence gates and limits on HA/DR conclusions.
6. [Private AKS lab](docs/aks-lab.md) — implementation detail and operating contracts.
7. [Technical references](docs/lab-guide.md#technical-reference) — requirements, decisions and clearly labeled archives.

The executive summary embeds the [App Service architecture](docs/diagrams/04-private-linux-app-service.svg) and [AKS architecture](docs/diagrams/06-private-aks-zone-lab.svg). The [diagram index](docs/diagrams/README.md) separates these measured designs from the historical Container Apps drawings.

## Publication and private context

Keep accounts, tenant/subscription identifiers, resource-group names, authentication paths, policy records, manifests, credentials and raw evidence in ignored `.local\` and `.azure\` paths. Publish sanitized architecture and results. The [environment example](config/environment.example.json) documents the existing App Service configuration; it does not establish AKS deployment readiness.

Run the publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

Git ignore rules do not protect full-folder archives or remove already-committed data. A local commit implies no remote publication. Resource-group deletion alone does not certify removal of soft-deleted vaults, service backups or audit retention.

Git tag `baseline-before-app-service-refactor` preserves the earlier Container Apps implementation. Its [execution history](docs/first-cycle-results.md) retains its original platform attribution.
