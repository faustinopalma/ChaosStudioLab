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

The new comparison is authorized on 7 November 2026 and selects Sweden Central after regional qualification. Live qualification completed at about 10:42 UTC: AKS 1.35.9 on Azure Linux 3.0 has nine Ready nodes across seven VMSS, with six .NET 10 pods on six user nodes across three zones. HTTPS, authentication, idempotence and checksum smoke checks passed using the pinned private ACR image digest. Private API, PostgreSQL, registry and vault DNS resolved inside approved subnets.

Workspace discovery and non-fault exact-node, selected-zone and database validations passed. The original DNS A-record race, bootstrap HTTPS timing, singleton DNS verifier and PC local-port issue are recorded as [provisioning/troubleshooting history](aks-results.md#provisioning-and-troubleshooting-findings). Existing cluster/database resources and the qualified image were preserved through these narrow repairs.

BASE-001 passed at about 11:03 UTC: 12,001 successful business operations, zero failures/drops, 601 successful canaries, 100% business success and successful-operation p95 11 ms. Five-minute warmup passed and all acknowledged writes/checksums were retained. The ten-minute configured baseline took 609.234 s including finalization.

An initial node-test preparation attempt failed before load or injection when singleton VM selection became a scalar. After repair and one-/three-VM entrypoint fixtures, the actual retry began at 11:14:14 UTC and native acceptance occurred at 11:15:04. That original genuine HA-NODE-001 completed with at least 300.292 s independently sustained power-off and successful native/caller auditing.

The required first 300 post-effect seconds had 75 failed business operations among 6,000, giving **98.75%: FAIL** against 99%. The whole twelve-minute phase reached 99.3541667%, passing its configured 99% aggregate threshold; it does not replace the first-five-minute gate. Successful-operation p95 was 11 ms and there was no complete canary unavailability. Offline independent evaluation passed recovery at 47.434 s into the qualifying 60-second window, 300-second stability and all-history retention. These separate PASS results preserve the original availability FAIL.

Nine Ready nodes and six Ready pods recovered automatically, but only five distinct workers hosted those pods. Hard hostname anti-affinity and private Service Local routing were subsequently applied outside measurement and qualified at 11:46:14 UTC. The actual five-second/two-probe HTTP `/healthz` ILB probe and per-pod health/checksum traffic qualified six distinct workers across three zones, without changing thresholds, private IP, TLS or immutable image/business revision. The original FAIL remains recorded.

Bicep/private invariants, native contracts, effect fixtures and owned Kubernetes server dry-run/diff passed before applying the correction. The diff was limited to Deployment anti-affinity, Service routing/probe settings and server-allocated `healthCheckNodePort`; namespace, service account and PDB remained unchanged.

Fresh corrected BASE-001 passed: warmup 6,001 business successes, p95 10 ms and 301 successful canaries; baseline 12,001 successes, p95 11 ms and 601 successful canaries; zero failures/drops in both. All acknowledged writes/checksums were retained and final six-worker/three-zone placement requalified.

The corrected twelve-minute node case passed native/identity audit, at least 303.8277 s power-off, first-five-minute availability at 99.4666667%, recovery at 0.732 s and automatic six-worker/three-zone restoration. It remains **FAIL** because none of 362 complete candidate stable windows qualified. Late failures through 12:22 left less than five stable minutes before measurement ended at 12:25:24.

Initial analysis INCONCLUSIVE was saved. An evaluator repair recognizes expected unscheduled Pending replicas while rejecting unscheduled non-Pending pods; unchanged raw data was re-evaluated without another injection. Subsequent fault phases use 18-minute load horizons and bounded 20-minute observers, retaining rates, caps, native duration and thresholds without architecture/image change or baseline reset.

The eighteen-minute node case completed **FAIL** at the unchanged first-five-minute gate: 63 failures among 6,000 operations gave 98.95%, versus at most 60 failures for 99%. Recovery passed at 39.181 s and a complete 300-second stable window passed at 99.9% business success; verified power-off lasted 306.1511 s. Full-phase success was 99.5509467%, automatic six-worker/three-zone restoration and all-history retention passed. Longer observation resolved stability coverage only; the real availability miss remains.

Node diagnostics recorded 458 failed business attempts and 51 failed canary attempts, all status 0 and about eight seconds long, recurring from 12:42 to 12:52. Root cause is unproven; preserve the measured FAIL rather than repeatedly rerunning for a favorable outcome.

Selected-zone compute shutdown also completed **FAIL**. Three selected VMs were off for 304.0433 s, six others remained running, and surviving traffic came from zones 2/3. First-five-minute business success was 97.85% (129 failures/6,000); full-phase success was 98.9629630%, both below 99%. Recovery 64.320 s, a 300-second stable window at 99.9%, automatic six-worker/three-zone restoration and all-history retention passed.

Final AKS reconciliation verified **37,659 of 37,659 acknowledged writes across ten history runs**, with zero loss/checksum mismatch. Earlier DB/zone/node checkpoints verified 32,330/nine, 26,966/eight and 21,594/seven. Progressive AKS counts remain separate from historical App Service totals.

DB failover reconciled to **overall FAIL** at 98.0093514% full-phase success against 99.9%, including 113 dropped business operations and 20 dropped canaries. Native/declared-identity audit, recovery 28.551 s, complete stable service and role swap passed. The original topology observer exited on one ten-second ARM GET timeout, while dependency observation and load completed.

Initial pipeline FAIL and the interrupted topology trace remain preserved. Unchanged raw evidence was retrieved/reconciled without resubmitting a fault; recovery uses complete independent dependency samples and actual role inventory. Future observers diagnose known transient ARM timeouts/429/5xx, discard entire incomplete samples and continue within the unchanged 30-second maximum gap; unauthorized errors remain fatal.

Combined load began at 14:01:44 UTC, with database-first triggering. It completed **overall FAIL** at 97.4445628% full-phase success against 99.9%, including 118 business/20 canary drops. Both native operations and authenticated identities, both observers, effects, overlap, recovery 28.855 s, 300-second stability, retention and final placement passed.

Observed power-off at 14:03:09.8203411 was bracketed by database 503 requests at 14:03:02.2493908 and 14:03:15.5460861, with no intervening healthy dependency observation. This supplies independent overlap proof. Recovery/stability PASS does not erase full-phase availability FAIL.

The harness preserves independent effects before final-layout checks and aggregates full-phase availability failure into overall case FAIL. Database/combined recovery PASS can remain independently recorded alongside overall FAIL when availability misses its gate. No complete HA PASS is claimed.

AKS Standard, static node counts and six single-node user pools allow the native VMSS shutdown Action to isolate one application node. Selected-zone shutdown targets exactly three owned VMSS: the system pool and logical user pools z1a/z1b, with zone 1 selected. This includes the zone-1 system VM and both application nodes while avoiding empty-zone matches on the four other user pools.

The design requires six application pods across six user nodes in three zones, with three additional tainted system nodes. PostgreSQL remains a private zone-redundant managed dependency. The application moves to a .NET 10 container using the existing source. The API server, application ingress, registry, vault and database have private access paths.

The initial AKS templates omit AMPLS and application Log Analytics deployment. Application logs use the private Kubernetes API, and independent runner observations/raw business measurement logs remain private. Read-only live checks found a separate Defender telemetry exception: enabled AKS security monitoring/gating references a default regional Log Analytics workspace with public ingestion/query enabled. Actual all-security-telemetry privacy is therefore unqualified.

The original 24 unrelated resource IDs/complete returned metadata remain unchanged, but protected inventory grew to 25 after that workspace appeared at 10:56:57 UTC outside the four owned groups. Correlated Started/Accepted/Succeeded Activity Log writes authenticate the subscription's Defender for Containers managed identity, and the AKS profile references the created workspace. Managed creation is independently proven; scope delta remains **FAIL**. The external group remains untouched for operator review, with no automatic deletion/governance change/exemption renewal. See [managed security telemetry and scope limits](experiment-limits.md#managed-security-telemetry-and-external-scope-delta).

The completed eighteen-minute node service FAIL remains separate from the hard scope delta FAIL; proven Defender attribution does not waive either acceptance boundary.

Seven-minute (`PT7M`) native shutdown definitions provide margin for independent samples to establish at least 300 continuous seconds physically off. The runner reads node-group power states with Reader access; the Chaos identity has Virtual Machine Contributor and Reader for fault execution and reads. Actual power states, Kubernetes readiness, surviving capacity, and any AKS restart or replacement determine the sustained-effect verdict.

The workload's Kubernetes readiness probe checks process liveness to retain endpoints during transient database outages. Explicit `/health/ready` and independent business observations retain database-health qualification. Recovery must start a qualifying 60-second window within 180 seconds, followed by 300 stable seconds at the approved service targets. A full physical-zone-disaster verdict still requires broader fault coverage. See the [test matrix](aks-lab.md#test-matrix) and [scope limits](experiment-limits.md#aks-compute-shutdown-and-physical-zone-scope).

The original execution is complete; [AKS results](aks-results.md) preserve measured fault FAILs, physical full-zone BLOCKED and original final private qualification PASS. The subsequent repair deploys a bounded confirmed-order cache and HTTP/1.1 ingress; unchanged native-suite reruns are in progress. Four groups remain active during measurements. Final inventory records 87 owned resource/definition/exemption IDs; the original 24 unrelated resources remain unchanged plus the external Defender workspace, so strict scope delta remains FAIL.

Read [timing attribution](aks-results.md#elapsed-time-and-attribution): manifest-to-final-verification elapsed time was 5 h 05 min 36.744 s; ten unique k6 intervals totalled 2 h 07 min 57.297 s. Recorded retention is an incomplete subtotal, parallel infrastructure stages overlap, and research/diagnosis/manual reconciliation/operator gaps are not fully timed.

The later operator instruction authorizes teardown after successful native-suite reruns. Follow the [workload → managed-node verification → operations → network sequence](aks-lab.md#operator-managed-cleanup-order). Never delete the pre-existing default regional group or Defender workspace. No automatic teardown or governance change was performed.

The private operator report is `.local\<run>\OPERATOR-RESULTS.md`: exact four-group names/87-ID inventory, private-access restart instructions and manual deletion steps remain ignored. Manifest/handoff persist final FAIL, health PASS and all retained writes. The original series stopped only the temporary PC tunnel helper. Current repair stages reopen private management and retain Azure resources until the qualified-success cleanup gate.

## Technical reference

| Reference | Scope and reading caution |
| --- | --- |
| [Accepted decisions](../DECISIONS-ACCEPTED.md) | D24 governs the new AKS comparison; D17-D23 retain App Service decisions |
| [Implementation specification](specification.md) | Current AKS navigation and detailed historical App Service requirements; older Linux snapshots retain explicit historical attribution |
| [Implementation contracts](implementation-contracts.md) | App Service native selector, effect, audit, recovery and retention contracts; use the AKS plan for new VMSS targeting |
| [Development readiness](development-readiness.md) | App Service deployment and provider qualification history; separate from AKS deployment readiness |
| [Platform research](research.md) | Current AKS navigation, final Windows comparison and historical Linux qualification/native contracts |
| [Editable private AKS architecture SVG](diagrams/06-private-aks-zone-lab.svg) | Workload data plane, one-pod-per-host topology, compute boundary and explicit governance-managed public telemetry box outside four owned groups |
| [Diagram index](diagrams/README.md) | Existing App Service and historical Container Apps diagram index |
| [First-cycle results](first-cycle-results.md) | Original Container Apps/PostgreSQL measurements and cleanup findings |
| [Historical architecture guide](architecture-guide.md) | Retired Container Apps/Automation walkthrough |
| [Historical cycle method](lab-cycle-method.md) | Retired autonomous cycle procedure and troubleshooting history |

## Before sharing

Publish sanitized findings and references. Keep identifiers, accounts, group names, ownership manifests, certificates, tokens and raw evidence in ignored private paths. Run `pwsh .\tests\Test-Publication.ps1` from the repository root before sharing, explicitly selecting the current lab's private configuration and publication-values files. Defaults may refer to an older environment.
