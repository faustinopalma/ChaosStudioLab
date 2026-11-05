# Private Linux App Service execution results

Evidence date: 5 November 2026, UTC. The native database case is still in progress.

## Outcome

The corrected private Linux architecture and complete **BASE-001 are PASS**. Six actual workers participated across three physical zones before and after the baseline. Required application/combined coverage is **BLOCKED** by actual native provider target-validation failures, so the complete suite has no PASS.

The earlier external PostgreSQL stop remains historical evidence. Under the operator's 5 November autonomous authorization, the existing server was restored to private Ready/Healthy zone-redundant HA at approximately 06:25 UTC. The first raw ARM start ended Failed/GatewayTimeout and was reconciled; provider-specific CLI start succeeded. The externally deallocated sole runner was also restored. Actual application configuration had drifted to `alwaysOn=false`; an in-place premeasurement repair restored Always On and the six-worker inventory. The cause of that drift remains unknown.

The exact-instance process-crash execution was accepted at 08:04:15 UTC and failed provider target validation at 08:04:26 UTC. Fresh discovery and repeated validation reproduced the internal resource error. An additional Switzerland North Workspace also rejects both instance and zone targets against the unchanged Spain Central application. PostgreSQL validation succeeds; its actual native failover was accepted at 08:54:09 UTC and measurement/reconciliation are in progress. No application fault was manually simulated.

## Deployed and observed capabilities

| Gate | Actual evidence |
| --- | --- |
| Linux plan | Spain Central, P1v3, six workers, `reserved=true`, `zoneRedundant=true`, `maximumNumberOfZones=3`, `perSiteScaling=false` |
| Three physical zones | Six actual instance IDs; two workers each in `spaincentral-az1`, `spaincentral-az2`, `spaincentral-az3` |
| Application participation | Every worker served successful live health and authenticated checksum-verified business reads |
| Private ingress/publication | Approved application Private Endpoint, separate outbound Integration subnet, private application/SCM DNS, successful checksummed private SCM publication |
| Public application/SCM | Actual external requests returned HTTP 403; public application access is Disabled |
| Private PostgreSQL | Public access Disabled; private authenticated reads/writes and restored Ready/Healthy zone-redundant HA verified before native injection; primary zone 1 and standby zone 2 |
| Management | One private runner in Sweden Central, global VNet peering, existing Bastion path; no runner public IP |
| Modern Chaos | Sweden Central Workspace discovered exact Spain Central targets; an additional owned Switzerland North Workspace supports a bounded instance/zone validation comparison |
| Removed active topology | Container Apps, registry/image path, Automation Account, Hybrid Workers, lifecycle storage and automatic suspension/scheduling are absent from active templates |

Placement and participation were verified again before the native app case. Actual `zoneRedundant=true`, `maximumNumberOfZones=3` and `alwaysOn=true` are direct live guards. These observations remain point-in-time evidence. Resources remain deployed.

## Measurements and individual verdicts

Complete BASE-001 finished at **07:29:16 UTC**:

| Phase | Business operations | Successful canaries | Business success | Successful p95 | Unique writes retained |
| --- | ---: | ---: | ---: | ---: | ---: |
| Five-minute warmup | 6,001 | 301 | 100% | 121 ms | 1,507 |
| Ten-minute baseline | 12,000 | 601 | 100% | 122 ms | 3,006 |
| Twelve-minute load around rejected app execution | 14,401 | 720 | 100% | 123 ms | 3,606 |

All three phases had zero failed business operations/canaries and zero scheduled-operation/canary drops. Every issued write was resolved and every acknowledged write retained/checksummed. Complete history after the app case reverified **11,132 measurement writes across five runs**, with zero acknowledged loss, plus the separately verified accumulated private-smoke journal. The rejected app execution caused no established process-crash effect; its healthy-load metrics provide no HA recovery verdict.

Earlier five-minute runs with 1,506 and 1,507 writes are included in that history. Their transient Bastion transfer failures were repaired in place; original evidence was recovered. Completed archives now have explicit bounded transport retries without resubmitting measurement or faults. An exact observer-readiness handshake resolves the separate concurrent SSH startup issue.

| Test | Verdict | Evidence boundary |
| --- | --- | --- |
| BASE-001 | **PASS** | Complete warmup/baseline, all-six-worker/three-zone participation and exact write retention verified |
| HA-APP-001 | **BLOCKED** | Actual accepted execution failed target validation; no successful native Action or independently evidenced process replacement |
| HA-APP-ZONE-001 | **BLOCKED** | Actual selected-zone case returned RequiresAttention/internal resource error before load/fault; mapping and two selected workers remain verified |
| HA-DB-001 | **RUNNING** | Non-fault validation passed; actual native failover accepted at 08:54:09 UTC; effect/recovery/retention verdict pending |
| HA-COMBINED-001 | **BLOCKED** | Actual combined-case preflight rejects the application target; no combined fault or disruptive overlap established |
| HA-AZ-001 | **BLOCKED** | No supported correlated real-zone injection/evidence |

Application recovery and combined overlap remain unmeasured because native application injection failed qualification. Historical/current retention was reverified after readiness restoration and after the rejected app execution. Final post-database-fault reconciliation remains pending.

## Linux native-runtime findings

The live regional Kill process schema explicitly describes Linux `dotnet/node` workers. Actual logical/physical mapping was obtained from the approved subscription. The Windows-only Cache Stampede with Process Crash template supplies a documented Windows template-coverage advantage; comparative native runtime/recovery results remain unavailable. See the [OS comparison](research.md#linux-baseline-and-windows-test-coverage).

Distinct provider findings were preserved:

1. Scenario creation rejected an empty `ProcessName` with `Properties.Actions[0].Parameters[0].Value: The Value field is required`, despite successful ARM validation. The explicit `dotnet` process name was revalidated and both deterministic Scenarios/configurations were successfully created.
2. The actual Linux instance-process read endpoint returns `Conflict(The dotnet-monitor tool is not configured to run)`. Completed read-only private container inspection independently found the application, DiagServer and dotnet-monitor processes. The documented monitor-disable setting is absent, and the runtime catalog lists the configured .NET 10 stack as Active. No verified monitor-enable remedy was found.
3. Actual execution and repeated non-fault validation fail with `ScenarioExecutionTargetValidationError`, resource error `-1`, an internal service error and private provider-reference IDs. Fresh discovery and a second Workspace region reproduce the failure. Permission-error arrays are empty; verified roles and successful PostgreSQL validation do not establish the app provider's root cause.
4. The preview returns short configuration Scenario names and normalizes canonical source Action URNs to friendly versioned IDs. Exact-parent resolution and pinned Action mappings are tested. Successful validation can omit the optional `validationErrors` property; the observed omission was fixed/tested after the first database preflight failed locally without submitting load or a fault.

Current results apply to the tested private Linux/runtime/selector configuration. They establish no blanket Linux restriction or Windows recovery advantage. Linux, six workers, three observed physical zones and private access remain unchanged. No guessed flag, near-end-of-support runtime downgrade, Windows switch, public SCM fallback or manual process termination was applied.

## Timing breakdown

These are recorded foreground-stage wall times, including their guards/previews and client overhead. They are distinct from pure Azure provider provisioning time.

| Successful deployment/configuration stage | Seconds |
| --- | ---: |
| Owned scope and finite exemption | 113.477 |
| Qualifying Spain Central plan | 138.049 |
| Identity prerequisites | 276.137 |
| Private infrastructure | 1,543.884 |
| Runner installation | 273.288 |
| Private application/bootstrap/publication | 798.066 |
| Corrected native process definitions | 192.783 |
| Refreshed native selection definitions | 204.507 |
| Isolated Switzerland North Workspace stage | 237.879 |
| **Recorded successful stage total** | **3,778.070** |

Separate troubleshooting evidence includes the rejected native-definition attempt (**188.607 s**) and recovered original-write verification (**104.151 s**). The initial baseline attempt's total envelope was **436.205 s**, including its **306.217 s** guest warmup and preflight/transport overhead. Do not add that envelope to its contained measurement as independent time. Regional search, compilation, interactive diagnosis and other foreground checks have separate raw logs; a complete exclusive troubleshooting total was not instrumented.

Complete BASE-001 took **1,403.890 s**, including guest warmup **306.198 s**, guest baseline **610.330 s**, qualification, transfer and retention. The rejected app case took **2,060.966 s**, including its **732.015 s** guest load and **669.368 s** complete-history reconciliation. The Switzerland North postdeployment discovery/validation diagnostic stage took **44.908 s**. These nested or overlapping envelopes must not be added as exclusive wall time. Database measurements remain in progress; application recovery/combined-overlap durations do not exist.

## Source validation and continuation

Local fixtures verify deterministic selectors, owned polling, explicit failed/uncertain operations, compiled execution target/identity/parameters, all-selected-worker process replacement, complete post-effect accounting, database role swap, recovery/stability, overlap rejection and retention of every earlier smoke/measurement write. The exact native overlay passed compilation, ARM validation and literal-owned four-resource preview before creation. Release API build and nine API tests passed.

The native harness remains **unqualified end-to-end**. It preserves an unresolved accepted submission and blocks another injection until reconciled. A failed runtime Action cannot produce a suite PASS. Final history verification revisits earlier run files as well as the current phase.

The active harness synchronizes and checksums all eight private measurement tools before every case and verifies provider non-fault validation before starting load. Validation-specific RequiresAttention cannot become execution success. Signed polling material remains private; accepted/uncertain operations are reconciled before another fault. Provider failures receive separate BLOCKED verdicts. Any subsequent repair must retain exact placement, private paths, the operator-selected Linux platform, recent package/instance-specific baseline and the provider's twenty-minute failover cooldown.

## Remaining resources and manual deletion

The previous inventory contained **58 top-level ARM resources**: network 26, workload 22 and operations 10. The isolated regional qualification added a Switzerland North Workspace and four native children; final inventory will be refreshed after the database case. Resources include the six-worker plan/application, private HA database, one private runner, Bastion/NAT/public IPs, VNets/peering, Private Endpoints/DNS, vault/identities/monitoring and modern Chaos definitions. Child resources/roles remain in the private manifest. The finite public-IP exemption remains live.

No automatic deletion, Destroy, Suspend/Resume or purge occurred. The private operator report records exact current group names, profile, expiry, inventory and **unexecuted** deletion commands. When ready, the operator deletes the owned **workload -> operations -> network** groups. Azure-retained vault/backup/audit records can outlive group deletion; no purge or retention-policy change is implied.
