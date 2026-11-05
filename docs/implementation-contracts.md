# Implementation contracts

Updated: 5 November 2026.

## Operator authorization

The operator withdrew the previous project-level operational prohibitions and requested autonomous completion of the deployed laboratory, without a cost ceiling. Starting the existing stopped database, repairing lab resources, maintaining required policy exemptions, selecting another capable region and executing the complete requested test suite are authorized. Continuation uses this authorization directly.

The currently selected implementation is Linux App Service in Spain Central, with the private runner and Chaos Workspace in Sweden Central. Regions are independently configurable; live provider qualification determines eligibility. The laboratory remains available after measurement for subsequent operator teardown.

Authentication, actual Azure authorization/policy responses, resource ownership, private connectivity and measurement completeness remain technical validation contracts. They provide evidence for safe execution and meaningful verdicts. The archived Container Apps/controller decisions are recoverable from Git.

## Architecture and identity

- One Linux App Service Web App on a fixed-six Premium plan: `reserved=true`, `zoneRedundant=true`, `maximumNumberOfZones>=3`, `perSiteScaling=false`.
- Six distinct application instances, healthy and serving authenticated business requests across three observed `physicalZone` values.
- Outbound VNet Integration and inbound Private Endpoint on separate subnets; private application/SCM DNS and disabled public application data-plane access.
- Private PostgreSQL Flexible Server, zone-redundant HA with Healthy standby and distinct primary/standby zones, public access Disabled.
- One private runner using the established Bastion path. Workload/operations VNets are globally peered.
- Four user-assigned identities: runtime, migrations, runner and Chaos execution. Directory registrations and resource permissions are separately verified.
- Modern Chaos Workspaces, Scenarios, configurations and native Actions. Reader discovery and exact-target execution permissions are independently checked.

Ownership uses the existing deployment GUID, exact resource-group IDs, deployed outputs and recursive resource inventory. Source-derived ARM validation and fully expanded effective previews cover each changed deployment surface. Owned modifications are supported for in-place troubleshooting.

## Publication and execution

The package is built from current source, checksummed, transferred to the single runner and published through private SCM. App/SCM and dependency DNS resolve through private zones. Actual application responses establish runtime and business readiness. Publication and every test read `config/web` directly and require `alwaysOn=true`; a configured six-worker plan alone does not keep an idle application resident.

PC orchestration uses visible stage logs and bounded command deadlines. Each measurement has a fresh RunId, identified load owner, recorded start/end times and separate private observation. Provisioning, troubleshooting and measurement timings are reported separately.

Every baseline and native case synchronizes the current runner/load/observer/durability tools in one package and verifies every private source checksum before qualification or load. Reports retain those hashes. An older publication bundle therefore cannot silently run an obsolete verifier or canary.

Completed raw-evidence archives use at most three transfer attempts for explicit transient SSH connection failures. Each retry is logged and retrieves the same archive; authentication/host-key failures and exhausted retries fail explicitly. Measurement and native fault submission are never repeated by this transfer retry.

Active source implements the App Service workflow. The obsolete cycle, Automation/Hybrid Worker, lifecycle control-store, Suspend/Resume and registry/image interfaces have been removed.

## Native Action contracts

The current pinned native API is `2026-08-01-preview`.

| Test | Native configuration and independent evidence |
| --- | --- |
| BASE-001 | Five-minute warmup and ten-minute baseline, six-worker/three-zone participation and complete write reconciliation |
| HA-APP-001 | `urn:csci:microsoft:appservice:killprocess/1.0.0`, `ProcessName=dotnet`, one exact current `InstanceIds` value and `Zones=[]`; actual process replacement and surviving-worker traffic |
| HA-APP-ZONE-001 | Same native Action with `InstanceIds=[]` and one verified logical-zone selector; replacement of all actual selected-zone processes |
| HA-DB-001 | `urn:csci:microsoft:azurepostgresql:failover/1.0.0`, forced mode `1`, `RestoreOnStop=false`, `SkipIneligibleServers=false`; native terminal success, dependency disruption and Healthy primary/standby zone swap |
| HA-COMBINED-001 | Both Actions, with application replacement independently bracketed by database dependency failure; independently observed disruptive overlap |
| HA-AZ-001 | Supported correlated infrastructure-zone loss and affected-zone evidence across the relevant application path |

Scenario string-valued parameters serialize selector arrays. The process name is explicit because actual Scenario creation rejects an empty value. Intent is saved before submission; accepted/uncertain executions are reconciled before another submission.

The preview configuration GET returns `properties.scenarioId` as a short Scenario name. Resolve it against the configuration's exact owned parent resource ID and verify the binding; full IDs are accepted only when they identify that same parent.

Scenario GET normalizes the two selected Actions to `microsoft-appservice-killprocess/1.0` and `microsoft-azurepostgresql-failover/1.0`. An explicit version-pinned mapping connects those observed identifiers to their canonical execution fault URNs; unknown Actions/versions fail validation.

Actual execution identity, target IDs, canonical Action, compiled parameters and Action summary must match the selected configuration. Process crashes have discrete semantics. HA-AZ-001 retains a separate verdict based on genuine infrastructure-zone evidence.

Linux runtime/selector support is verified against the actual Action and endpoint. The [Windows comparison](research.md#linux-baseline-and-windows-test-coverage) records the documented Windows-only cache-stampede template and any observed runtime advantage. Unavailable or unqualified required coverage receives an explicit BLOCKED verdict.

## Measurements and durability

- Twenty business operations/second, 80% reads and 20% writes; independent one-second authenticated read/write canary.
- Baseline and stable business success at least 99.9%, successful p95 at most one second.
- App-only observation: complete first five post-effect minutes, success at least 99%, p95 at most two seconds, complete canary unavailability at most five seconds.
- Database/combined recovery: at most 180 seconds to a qualifying complete sixty-second recovery window; at least ten post-injection minutes and a continuous five-minute stable period.
- Provider failover spacing: at least twenty minutes after the previous terminal completion, with a Healthy standby.
- Reconcile every unique issued write, including response-loss outcomes, and verify every acknowledged write's checksum and retention across every previous run.

The independent observer records frontend HTML errors without terminating during an application restart. Database disruption and combined overlap require an authenticated application response with an explicit PostgreSQL `unavailable` or `timeout` status; a generic HTTP 503 supplies insufficient dependency evidence.

Native load starts after the independent observer emits its exact RunId readiness marker through authenticated SSH. This handshake has a sixty-second deadline and serializes private connection establishment before concurrent measurement.

Each test reports submission, acceptance, actual effect, terminal completion, recovery, errors/drops, latency and durability separately. A complete-suite PASS requires every mandatory application/database/combined test to pass its actual acceptance gates.

## State and publication

Private environment, operational authorization, manifest, policy records, raw responses and measurement files remain under ignored local paths. Publishable source/docs contain sanitized results. The publication guard runs before a local Git checkpoint. Final reporting records remaining resources and exact operator teardown commands in the private handoff/report.
