# Lab guide

[Repository overview](../README.md) · [Accepted decisions](../DECISIONS-ACCEPTED.md)

This is the reading entry point for the resilience laboratory. Follow the measured App Service history first, then the private AKS comparison, and finally the detailed references.

## The question and the evidence

The application acknowledges a write after PostgreSQL commits it. The client records the operation identifier and expected checksum. Controlled faults then test continued business service, automatic recovery and subsequent reconciliation of every acknowledged write.

These questions have separate answers:

- **Availability:** how many scheduled business operations and independent canary requests succeeded throughout the measured phase?
- **Recovery:** when did service regain a complete qualifying recovery window, followed by stable operation?
- **Durability:** does every acknowledged write remain readable with its expected checksum?
- **Fault coverage:** which processes, compute nodes and dependencies actually experienced the intended effect, for how long?

A successful recovery or retention check can coexist with failed full-phase availability. A provider-accepted Action also needs independent evidence of its effect.

## Read in this order

| Step | Document | What it answers |
| --- | --- | --- |
| 1 | [App Service execution results](app-service-results.md#windows-comparison-variant-complete-native-suite-6-november) | What actually ran on Windows and Linux, including failed and blocked attempts |
| 2 | [Experiment limits](experiment-limits.md) | What process crashes, forced failover and compute shutdown can establish |
| 3 | [Private AKS lab](aks-lab.md) | Why the new topology permits exact-node and selected-zone compute targeting; how tests are gated |
| 4 | [AKS results register](aks-results.md) | Which facts are qualified, which outcomes remain pending, and what evidence a verdict needs |
| 5 | [Technical reference](#technical-reference) | Where to find detailed App Service contracts, decisions, platform research and older histories |

## App Service: measured history

The Windows comparison on 6 November 2026 used six workers balanced across three observed physical zones. Baseline passed at 100% success and p95 123 ms. Native exact-instance and selected-zone process crashes passed with zero failed business operations. Process replacement started 12.7 s after acceptance for the exact-instance case and 11–13 s for the two selected-zone workers.

PostgreSQL forced failover passed recovery and durability with 36.359 s recovery; full-phase availability failed at 97.347%. The combined case passed recovery, durability and independently observed overlap with 34.989 s recovery; full-phase availability failed at 97.324%. Database failures bracketed the process replacements, providing overlap evidence independent of native Action scheduling.

All 92,616 acknowledged measurement writes across 31 Linux and Windows runs were retained with matching checksums. Linux process deletion was unsupported wherever process listing worked. HA-AZ-001 stayed BLOCKED without injection.

The operator deleted the App Service lab groups on 6 November at 09:43 UTC. Seven unrelated groups and their 24 resources were verified unchanged. The original result documents retain their execution-time descriptions, including statements that resources were then deployed; this later lifecycle update belongs to the comparison's current status.

## AKS: new comparison

The new comparison is authorized on 7 November 2026 and selects Sweden Central after regional qualification. Scope and identities are deployed; private AKS/PostgreSQL infrastructure is provisioning after ARM validation passed with 42 Creates and five owned-identity Ignores. These validation counts supply no completed workload or experiment verdict.

AKS Standard, static node counts and six single-node user pools allow the native VMSS shutdown Action to isolate one application node. Selected-zone shutdown targets exactly three owned VMSS: the system pool and logical user pools z1a/z1b, with zone 1 selected. This includes the zone-1 system VM and both application nodes while avoiding empty-zone matches on the four other user pools.

The design requires six application pods across six user nodes in three zones, with three additional tainted system nodes. PostgreSQL remains a private zone-redundant managed dependency. The application moves to a .NET 10 container using the existing source. The API server, application ingress, registry, vault and database have private access paths.

Unlike the historical App Service private Azure Monitor path, the initial AKS lab deploys no AMPLS or Log Analytics. Application logs are collected through the private Kubernetes API; the remote runner's independent observer and node-topology monitor provide raw evidence retained under ignored `.local\`.

Seven-minute (`PT7M`) native shutdown definitions provide margin for independent samples to establish at least 300 continuous seconds physically off. The runner reads node-group power states with Reader access; the Chaos identity has Virtual Machine Contributor and Reader for fault execution and reads. Actual power states, Kubernetes readiness, surviving capacity, and any AKS restart or replacement determine the sustained-effect verdict.

The workload's Kubernetes readiness probe checks process liveness to retain endpoints during transient database outages. Explicit `/health/ready` and independent business observations retain database-health qualification. Recovery must start a qualifying 60-second window within 180 seconds, followed by 300 stable seconds at the approved service targets. A full physical-zone-disaster verdict still requires broader fault coverage. See the [test matrix](aks-lab.md#test-matrix) and [scope limits](experiment-limits.md#aks-compute-shutdown-and-physical-zone-scope).

Resources remain active after execution until the operator orders stop or deletion. Pending AKS execution is recorded honestly in the [results register](aks-results.md); architecture approval supplies no measured PASS.

## Technical reference

| Reference | Scope and reading caution |
| --- | --- |
| [Accepted decisions](../DECISIONS-ACCEPTED.md) | D24 governs the new AKS comparison; D17-D23 retain App Service decisions |
| [Implementation specification](specification.md) | Detailed App Service requirements and acceptance objectives; its target/status text describes the earlier phase |
| [Implementation contracts](implementation-contracts.md) | App Service native selector, effect, audit, recovery and retention contracts; use the AKS plan for new VMSS targeting |
| [Development readiness](development-readiness.md) | App Service deployment and provider qualification history; separate from AKS deployment readiness |
| [Platform research](research.md) | App Service placement, runtime qualification, native contracts and original references |
| [Diagram index](diagrams/README.md) | App Service and historical Container Apps diagrams; they do not depict the new AKS topology |
| [First-cycle results](first-cycle-results.md) | Original Container Apps/PostgreSQL measurements and cleanup findings |
| [Historical architecture guide](architecture-guide.md) | Retired Container Apps/Automation walkthrough |
| [Historical cycle method](lab-cycle-method.md) | Retired autonomous cycle procedure and troubleshooting history |

## Before sharing

Publish sanitized findings and references. Keep identifiers, accounts, group names, ownership manifests, certificates, tokens and raw evidence in ignored private paths. Run `pwsh .\tests\Test-Publication.ps1` from the repository root before sharing.
