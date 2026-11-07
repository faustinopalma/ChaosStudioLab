# Azure Chaos Studio resilience lab

This repository compares recovery and acknowledged-write durability under controlled Azure application, compute and PostgreSQL faults.

**Start with the [lab guide](docs/lab-guide.md).** It connects the measured App Service experiments, their evidence limits, the new private AKS/PostgreSQL design, and the detailed technical references.

## Current status — 7 November 2026

- **App Service experiments are historical.** Their dedicated groups were deleted on 6 November at 09:43 UTC; seven unrelated groups and 24 resources were verified unchanged. Original results remain available.
- **The original AKS series is complete; architectural reruns are in progress.** Original final checks passed nine Ready Azure Linux nodes, six distinct Ready user workers across three physical zones, private API access and Healthy zone-redundant PostgreSQL. The later repair deploys a bounded immutable-read cache and HTTP/1.1 ingress on the existing private architecture.
- **The requested resilience suite has no complete PASS.** Baselines passed; every measured fault case failed a required availability, stability or placement gate, and physical full-zone coverage remains BLOCKED. Recovery and retention PASS remain separately reported.
- **All 37,659 of 37,659 acknowledged AKS writes across ten history runs were retained**, with zero lost writes or checksum mismatch. [Final AKS results](docs/aks-results.md) preserve earlier node failures, observer interruptions, setup corrections and independent combined-overlap proof.
- **Scope guard FAIL: one extra governance-managed telemetry resource.** Original 24 unrelated IDs/complete returned metadata are unchanged; inventory is 25 after a default regional Log Analytics workspace appeared at 10:56:57 UTC outside the four owned groups. Correlated Activity Log writes independently prove creation by the subscription's Defender for Containers managed identity, and AKS Defender references it. Public ingestion/query are Enabled. The external group remains untouched for operator review; qualified private workload paths do not establish all-security-telemetry privacy.
- **Teardown is authorized after successful native tests.** The later operator instruction supersedes the initial leave-running order. Preserve all failures and the physical full-zone BLOCKED boundary; delete only experiment-owned resources after qualified success. [D24](DECISIONS-ACCEPTED.md#d24-private-aks-comparative-architecture-and-operator-authorization) records the comparison and operating scope.

Resources remain active during repair measurements; the temporary private management tunnel is reopened for bounded stages. The ignored operator report at `.local\<run>\OPERATOR-RESULTS.md` contains exact group names/inventory, private-access restart instructions and manual deletion steps. Public docs intentionally omit those private identifiers.

## Original AKS outcomes

| Test | Overall verdict and required failure |
| --- | --- |
| BASE-001, original and corrected | **PASS**: 100% business success, baseline p95 11 ms |
| HA-NODE-001, final 18 min | **FAIL**: first-five-minute success 98.95%; recovery 39.181 s, stability and retention PASS |
| HA-ZONE-COMPUTE-001 | **FAIL**: first-five-minute 97.85%, full-phase 98.9629630%; recovery 64.320 s and retention PASS |
| HA-DB-001, reconciled | **FAIL**: full-phase 98.0093514% against 99.9%; recovery 28.551 s and retention PASS; interrupted topology trace preserved |
| HA-COMBINED-001 | **FAIL**: full-phase 97.4445628% against 99.9%; independently observed overlap, recovery 28.855 s, stability and retention PASS |
| HA-AZ-001 | **BLOCKED**: no physical full-zone injection; final guard exits 1 without Azure changes |

Manifest-to-final-verification elapsed time was **5 h 05 min 36.744 s**. Ten unique k6 measurement intervals totalled **2 h 07 min 57.297 s**; these are different accounting categories. See [timing attribution](docs/aks-results.md#elapsed-time-and-attribution) and [operator-managed cleanup order](docs/aks-lab.md#operator-managed-cleanup-order). No cleanup was performed after the final measurements.

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

1. [Lab guide](docs/lab-guide.md) — one navigable entry point.
2. [App Service execution results](docs/app-service-results.md) and [experiment limits](docs/experiment-limits.md) — measured behavior and boundaries.
3. [Private AKS lab](docs/aks-lab.md) — architecture, native node-shutdown targeting and acceptance.
4. [Final AKS results](docs/aks-results.md) — per-gate verdicts, complete-history retention, final inventory and timing attribution.
5. [Accepted decisions](DECISIONS-ACCEPTED.md) and the guide's [technical-reference index](docs/lab-guide.md#technical-reference) — detailed contracts and historical material.

The [editable private AKS architecture SVG](docs/diagrams/06-private-aks-zone-lab.svg) shows the workload data plane, one-pod-per-host placement, Local health probes and the lab-owned compute fault boundary. Its updated view explicitly includes the governance-managed public telemetry exception outside the four owned groups; see [limits](docs/experiment-limits.md#managed-security-telemetry-and-external-scope-delta).

## Publication and private context

Keep accounts, tenant/subscription identifiers, resource-group names, authentication paths, policy records, manifests, credentials and raw evidence in ignored `.local\` and `.azure\` paths. Publish sanitized architecture and results. The [environment example](config/environment.example.json) documents the existing App Service configuration; it does not establish AKS deployment readiness.

Run the publication guard before committing or sharing:

```powershell
pwsh .\tests\Test-Publication.ps1
```

Git ignore rules do not protect full-folder archives or remove already-committed data. A local commit implies no remote publication. Resource-group deletion alone does not certify removal of soft-deleted vaults, service backups or audit retention.

Git tag `baseline-before-app-service-refactor` preserves the earlier Container Apps implementation. Its [execution history](docs/first-cycle-results.md) retains its original platform attribution.
