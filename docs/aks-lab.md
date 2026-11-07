# Private AKS and PostgreSQL comparison lab

[Lab guide](lab-guide.md) · [Limits](experiment-limits.md) · [Results](aks-results.md) · [Decision D24](../DECISIONS-ACCEPTED.md#d24-private-aks-comparative-architecture-and-operator-authorization)

Design date: 7 November 2026. This document describes the authorized architecture and test contracts. Successful provisioning, baseline participation and fault outcomes require their own evidence in the results register.

## Objective and operating scope

Reuse the current application's committed-write/checksum model to compare private AKS service behavior with the measured App Service history. Add controlled infrastructure-node loss and sustained selected-zone compute loss, retaining separate availability, recovery, overlap and durability verdicts.

The operator authorized autonomous implementation, deployment, necessary repairs and testing. Work is orchestrated from the PC in bounded foreground stages with visible progress and logs. One private Ubuntu runner uses managed identity for publication and measurement. Leave the new resource groups active until the operator orders stop or deletion; preserve unrelated resources and ownership checks.

## Regional and platform qualification

| Item | Selected value or qualified prerequisite |
| --- | --- |
| Region | Sweden Central |
| Compute catalog | `Standard_D4ds_v5`, live unrestricted qualification in zones 1, 2 and 3 |
| Initial alternative | Italy North VM candidate restricted |
| AKS tier | Standard |
| Kubernetes catalog | 1.35.9 checked as supported; record the actual deployed version |
| Provisioning model | Static VMSS node pools; NAP and cluster autoscaling disabled |
| Networking | Azure CNI Overlay with Cilium |
| Application runtime | .NET 10 container using existing application source |
| Database | PostgreSQL Flexible Server 16; regional zone-redundant HA capability enabled |

AKS Standard was selected to use the supported VMSS node-fault path without NAP. Live catalogs establish prerequisites; allocation, private connectivity and measured workload participation remain execution gates.

## Private architecture

| Component | Intended path and responsibility |
| --- | --- |
| AKS API server | Private API access; public FQDN disabled; administration from the private runner |
| Application ingress | HTTPS through a private internal load balancer; no public application endpoint |
| Premium Azure Container Registry | Private endpoint; managed-identity build/publication and kubelet pull access |
| Key Vault | Private endpoint; managed-identity access to required application/runner material |
| PostgreSQL 16 | Private endpoint, disabled public data-plane access, Entra-only authentication, verified TLS |
| PostgreSQL HA | Zone-redundant; intended primary zone 1 and standby zone 2; verify live Healthy role placement |
| Private DNS | Resolution for registry, vault, database, API and application from their required callers |
| Application logs | Collection through the private Kubernetes API; no AMPLS or Log Analytics deployment in the initial lab |
| Private Ubuntu runner | Managed-identity publication, migrations, k6 measurements, independent observer and node-topology monitor |
| PC orchestration | Bounded foreground stages and visible local logs; all raw evidence retained under ignored `.local\` |

Managed-identity authorization and private network reachability need independent checks. A build service reaching a private registry also needs a verified network path; granting registry permissions alone cannot qualify publication. Record the actual build location and private push/pull proof.

The initial comparison preserves application logging and independent observations without adding Azure Monitor services. This differs from the historical App Service AMPLS query path. Add observability services only when an actual execution need justifies them, and record the resulting design change.

## Node and workload placement

The baseline contains **nine nodes**:

- Three dedicated system nodes distributed across zones 1, 2 and 3 and tainted to keep the application on user nodes.
- Six single-node user pools, each pinned to one zone and held at count 1.

The following names are logical pool labels; they disclose no deployed resource identifiers.

| Logical user pool | Zone | Node count | Baseline application pods |
| --- | ---: | ---: | ---: |
| z1a | 1 | 1 | 1 |
| z1b | 1 | 1 | 1 |
| z2a | 2 | 1 | 1 |
| z2b | 2 | 1 | 1 |
| z3a | 3 | 1 | 1 |
| z3b | 3 | 1 | 1 |

Configure topology spread for six baseline application pods across six user nodes and three physical zones. Qualify the actual placement, readiness and authenticated business participation of each pod; a desired replica count alone cannot establish six-node participation.

The baseline gate requires the expected node set, one system and two user nodes per zone, and the expected application build. Record system-pool layout from the deployed inventory without assuming one VMSS per system node. Surviving pods may reschedule during faults; record resulting placement and any scheduling/remediation behavior.

## Native shutdown targeting

The selected live native node VMSS shutdown Action exposes `GracefulShutdown` and `Zones`, with **no instance-ID selector**. Preserve its exact live contract and accepted parameters in private evidence. Do not introduce an unsupported instance selector.

### Exact node

Select one owned user-pool VMSS containing exactly one live VM instance. Correlate that instance with its Kubernetes node, physical zone and baseline application pod. The single-node pool shape provides the exact-node boundary. Block execution if the VMSS contains extra instances or no longer matches the baseline.

### Selected-zone compute

Enumerate **all owned AKS system and user VMSS**, then use `Zones=['1']` for the selected zone. The expected affected set is three nodes: the two user nodes in zone 1 and its system node. Verify that every expected node belongs to the owned target set and that no unowned VMSS is included.

Observe a continuous **five-minute physically-off interval** through ARM VM power states and Kubernetes NotReady, while independently confirming healthy surviving pods. Time the sustained window from observed effects on the full intended target set. Record actual stop/deallocation semantics, restore behavior and every AKS reconciliation or remediation event.

A replacement or restart that shortens the required sustained window produces a **FAIL** for that gate. Missing or ambiguous evidence prevents qualifying the effect. Process/pod faults retain separate attribution and cannot substitute for this compute test.

## Test matrix

| Test | Planned load phase | Fault and required evidence |
| --- | --- | --- |
| BASE-001 | 5 min warmup + 10 min baseline | Expected build, private paths, nine-node topology, six participating pods, healthy cross-zone PostgreSQL and complete load samples |
| HA-NODE-001 | 12 min | Exact single-node user VMSS shutdown; five-minute sustained power-off, NotReady, surviving service and verified restoration |
| HA-ZONE-COMPUTE-001 | 12 min | Shutdown across all owned VMSS selected for zone 1; expected three-node effect sustained for five minutes |
| HA-DB-001 | 18 min | Native PostgreSQL forced failover; independently observed dependency errors, Healthy primary/standby transition, recovery and retention |
| HA-COMBINED-001 | 18 min | Database-first failover; trigger selected-zone shutdown after observed dependency failure; independently prove business-effect overlap |
| HA-AZ-001 | Guard only | **BLOCKED** until supported physical full-zone injection and independent effect evidence exist; do not inject under the current plan |

Fault duration and load duration are separate measurements. Begin each case only after a successful current baseline and recheck the build, node set, pod participation, private paths and database health. If provider delays consume the observation budget, record incomplete coverage or extend within a separately recorded bounded stage; do not count pre-effect time as post-fault observation.

## Load and acceptance

Use k6 from the private runner with **20 scheduled business operations/s plus one independent canary/s**. Bound concurrency at **200 business VUs and 10 canary VUs**. Preserve the existing request mix and deadlines for comparison, and record their actual values.

| Gate | Acceptance contract |
| --- | --- |
| Baseline and stable service | At least 99.9% business success; successful-operation p95 at most 1 s |
| Compute-only service | First five post-effect minutes: at least 99% business success, successful-operation p95 at most 2 s, complete canary unavailability gap at most 5 s |
| Sustained compute effect | Every intended node physically off for a continuous 5 min, with correlated Kubernetes NotReady and healthy surviving pods |
| Database/combined recovery | Existing objective: at most 180 s from actual dependency disruption to the beginning of a qualifying 60-second recovery window |
| Qualifying recovery window | Complete expected samples; at least 99% business and canary success; successful-operation p95 at most 1 s |
| Stable post-fault period | Continuous 5 min at baseline success/latency targets; at least 10 min post-effect observation for database/combined cases |
| Operational recovery | Automatic application recovery; no manual application restart, endpoint change or database repair to obtain the verdict |
| Full-phase availability | Separately report business success, failures/drops and latency against the existing 99.9% service-success target |
| Durability | Every acknowledged write retained and readable with matching checksum across the complete attributable history |

The sixty-second recovery window is an observation interval. The inherited 180-second objective separately bounds the time to its beginning. Report both timings and the five-minute stable window explicitly.

Count scheduled dropped work and independent canary failures in their appropriate denominators. Successful-operation p95 must be labeled and accompanied by failed and dropped counts. Report service recovery separately from node restoration and full-phase availability.

## Evidence and publication gates

For each case retain:

1. Actual build/runtime, supported cluster version, node/VMSS/pod/zone mappings and PostgreSQL role state.
2. Exact owned native targets, Action contract, `GracefulShutdown`, zone selectors, identity/audit correlation and acceptance/completion timestamps.
3. Independent observer and node-topology-monitor samples, actual-effect timestamps, power-state/NotReady snapshots, private-API application logs, surviving pod/business health and sustained-window start/end.
4. Any AKS restart, replacement, reconciliation, rescheduling and service restoration.
5. Raw bounded load samples, offered rate, errors/drops, canary gaps, successful latency and full-phase denominators.
6. Observed dependency disruption, recovery/stable windows and independently bracketed overlap for the combined case.
7. Every acknowledged operation and checksum, complete-history reconciliation, per-gate verdicts and separately attributable elapsed times.

Keep raw identities, resource names, accounts and all raw evidence under ignored `.local\`. Publish sanitized counts, zone labels, timings, exact fault semantics and verdict reasons in [AKS results](aks-results.md). The [experiment limits](experiment-limits.md) remain part of any comparative conclusion.

## Official references

- [Chaos Studio guidance for AKS](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-aks-guidance)
- [Chaos Studio Scenarios](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios)
- [Resources supported by Chaos Workspaces](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
