# Development readiness assessment

Assessment updated: 4 November 2026.

## 1. Verdict

**The specifications support implementation of the bounded private laboratory and its first provisioning/test/destruction cycle. No additional architectural approval is needed for that scope.**

Actual Sweden Central provisioning, private database/image bootstrap, authenticated API integration, monitoring, full warmup/baseline and genuine PostgreSQL forced failover have passed. Measured business recovery was **38.624 seconds**, within the 180-second objective. The [execution report](first-cycle-results.md) is authoritative for separate full-phase availability, durability, lifecycle and cleanup outcomes, including failed attempts.

The complete specification also includes capabilities beyond this first cycle. Keep their engineering and acceptance gaps explicit. Successful component testing establishes evidence for its tested scope; full-zone qualification requires its own injection and correlation evidence.

## 2. Evidence and implemented contracts

| Area | Verified implementation or evidence |
| --- | --- |
| Ownership | Exact dedicated groups, deployment-instance tags, literal-ID previews, recursive deployment inventory and guarded deletion |
| Region | Subscription-level HA eligibility checked before deployment; real PostgreSQL cross-zone HA and internal zone-redundant Container Apps provisioned in Sweden Central |
| Private bootstrap | Canonical HTTPS package sources, supported PowerShell runtime, managed-identity SQL migration, immutable private image publication and private image pull |
| Application | .NET 10 API, nine unit tests, real authenticated create/read/checksum, idempotent replay, conflicting-payload rejection and unauthenticated-request denial |
| Load | Actual private k6 execution at 20 operations/second; five-minute warmup and ten-minute baseline passed with zero failed or dropped business operations |
| Monitoring | Application requests and container system events queried privately with source-table provenance |
| Database fault | Canonical service-direct Action, discovery of the exact server, native terminal success and independent primary/standby swap; complete recovery window passed |
| Durability | Repeatable whole-run private re-read of unique issued writes, acknowledged-write retention and resolution of unacknowledged outcomes; separate post-fault/post-resume verdicts |
| Lifecycle smoke | Real Suspend/Resume with observed resource postconditions, restored private short baseline and all 3,558 original acknowledged writes retained |
| Management | Bastion with authenticated SSH readiness; bounded noninteractive transfers; two live private Hybrid Workers with registration repaired and verified |
| Controller | PowerShell 7.4, atomic validated lifecycle context, fixed 24-hour deadline, never-early scheduling and full verification of server-assigned association IDs |
| Governance | Finite one-reference Public-IP waiver; live missing/expired/drift checks; near-expiry warning and manual create-or-extend instructions |
| Publication | Real account/environment data, validation state, raw evidence and keys isolated under ignored local paths; publication regression checks known identifiers and tracked ignored files |

The [implementation contracts](implementation-contracts.md), [operating method](lab-cycle-method.md), [specification](specification.md), [accepted decisions](../DECISIONS-ACCEPTED.md) and [illustrated architecture guide](architecture-guide.md) describe these boundaries.

## 3. Defined baseline

The approved baseline remains:

- Two directly peered VNets, private endpoints/DNS, operations NAT/Bastion and scoped identities; Azure Firewall and BYOIP remain excluded.
- Zone-redundant Container Apps with the six-to-twelve replica baseline and Dedicated D4 capacity.
- Private Entra-authenticated PostgreSQL with distinct primary and standby availability zones.
- Transactional idempotency, checksummed writes, bounded retries and separate liveness/readiness.
- Independent endpoint-attempt, business-operation and canary accounting, plus a separate evidence-based recovery verdict.
- Recovery within 180 seconds and zero lost acknowledged writes for the applicable qualified test.
- Exact customer-controlled teardown, supported vault purge, and explicit reporting of provider-created or mandatory-retention remnants.

Regional or adapter failures require diagnosis within these boundaries. Unsupported operations must be reported explicitly. The first cycle does not authorize weaker availability, public data access, a broader exemption or unrelated-resource deletion.

## 4. Remaining feasibility and acceptance gates

| Gate | Required completion or evidence |
| --- | --- |
| Full Chaos preview suite | Discovery, exact target, genuine execution and recovery evidence are recorded per run. Cancellation, interrupted-run recovery and the complete preview acceptance suite require separate qualification. |
| Replica fault adapter | Prove noninteractive execution against explicit replica IDs, five-minute readiness TTL, actual withdrawal/restoration and independent control during a database outage. |
| Combined faults | Demonstrate actual overlapping application withdrawal and database disruption; preserve both timelines and their shared recovery evidence. |
| Full-zone test | `HA-AZ-001` remains blocked until supported real-zone injection and evidence correlate that zone with the affected application path. Replica identifiers alone provide no zone mapping. |
| Lifecycle allocation | Record observed stop/start states, configured Dedicated minima and any separately observable allocated-node count. Preserve private access and cross-zone HA. See the execution report for the smoke-test result. |
| Disconnected automatic suspension | A real 24-hour disconnected soak, delayed dispatch, repeated reconciliation and PostgreSQL's later automatic restart still require validation. Registration and short smoke tests provide narrower evidence. |
| Random campaigns | Keep disabled until deterministic, preview, cooldown, cancellation and lifecycle-priority gates pass. |

## 5. Engineering contracts still to finish

### Crash-safe lifecycle and early-build protection

**Apply to:** specification sections 6 and 8, the lifecycle runbook, staged build controller and ownership manifest.

The current implementation uses an exclusive local test/destruction lock and a private Blob lease shared by the runner and runbook. Complete a unified versioned step journal, explicit fault ledger, stale-owner recovery and cancellation handoff before claiming general crash-safe orchestration.

The independent controller is registered after private readiness. An interrupted earlier build requires exact-manifest operator cleanup. Implement an independently enforced initial failed-build deadline; storing a timestamp alone provides no execution mechanism.

### Versioned state and output schemas

**Apply to:** specification section 7, local manifests, private lifecycle state and test-report writers.

Finish formal schema/version validation for configuration, ownership, runtime snapshots, journals, fault state and reports. Define authoritative state and reconciliation when local and private copies differ. Add the required consistent JUnit/Markdown export and partial-failure report contract across all entry points.

### Credential and interface lifecycle

**Apply to:** API/bootstrap identity contracts and specification section 8.

Live managed-identity migration and runtime grants work. Document and exercise diagnostic-token rotation and revision refresh, retained-data checks across broader recovery scenarios, and uniform non-mutating previews. Destroy supports `-WhatIf`; the other lifecycle commands do not yet implement the complete preview interface.

## 6. Decisions requiring the user

**No new decision is required to complete the currently authorized first cycle or to implement the remaining engineering contracts.**

Request a new decision when concrete evidence requires changing an approved requirement: weakening HA/private access, broadening ownership or policy scope, substituting a different fault meaning, or relaxing recovery/durability/deletion targets.

Deployment identifiers and exemption renewals remain private operational inputs. Future startup identifies a missing/expired waiver and directs an approved manual create-or-extend action; it does not renew the waiver automatically.

## 7. Next development sequence

1. Use the measured execution report and repeatable method as the bounded-cycle baseline.
2. Complete crash-safe state/journal contracts and early-build watchdog protection.
3. Qualify the explicit-replica adapter, cancellation paths and combined tests.
4. Execute the disconnected suspension soak and extended recovery checks.
5. Enable bounded seeded campaigns only after their gates pass.

The project can continue directly with implementation and targeted qualification. Its remaining work is concrete engineering and evidence collection.
