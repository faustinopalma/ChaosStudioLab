# Private Linux App Service execution results

Evidence date: 5 November 2026, UTC. Measurements, complete-history reconciliation and the eight-region Workspace comparison have finished.

## Outcome

The corrected private Linux architecture and complete **BASE-001 are PASS**. Six actual workers participated across three physical zones before and after the baseline. Required application/combined coverage is **BLOCKED** by actual native provider target-validation failures, so the complete suite has no PASS.

The earlier external PostgreSQL stop remains historical evidence. Under the operator's 5 November autonomous authorization, the existing server was restored to private Ready/Healthy zone-redundant HA at approximately 06:25 UTC. The first raw ARM start ended Failed/GatewayTimeout and was reconciled; provider-specific CLI start succeeded. The externally deallocated sole runner was also restored. Actual application configuration had drifted to `alwaysOn=false`; an in-place premeasurement repair restored Always On and the six-worker inventory. The cause of that drift remains unknown.

The exact-instance process-crash execution was accepted at 08:04:15 UTC and failed provider target validation at 08:04:26 UTC. Fresh discovery and repeated validation reproduced the internal resource error. Both selectors fail through all eight advertised Workspace regions against the unchanged Spain Central application. Actual native PostgreSQL failover succeeded: independently measured recovery and durability are **PASS**, while **full-phase availability is FAIL**. Its original harness failure and subsequent authoritative reconciliation are both preserved. No application fault was manually simulated.

## Deployed and observed capabilities

| Gate | Actual evidence |
| --- | --- |
| Linux plan | Spain Central, P1v3, six workers, `reserved=true`, `zoneRedundant=true`, `maximumNumberOfZones=3`, `perSiteScaling=false` |
| Three physical zones | Six actual instance IDs; two workers each in `spaincentral-az1`, `spaincentral-az2`, `spaincentral-az3` |
| Application participation | Every worker served successful live health and authenticated checksum-verified business reads |
| Private ingress/publication | Approved application Private Endpoint, separate outbound Integration subnet, private application/SCM DNS, successful checksummed private SCM publication |
| Public application/SCM | Actual external requests returned HTTP 403; public application access is Disabled |
| Private PostgreSQL | Public access Disabled; private authenticated reads/writes and Ready/Healthy zone-redundant HA verified before/after native injection; actual primary/standby changed from zones 1/2 to 2/1 |
| Management | One private runner in Sweden Central, global VNet peering, existing Bastion path; no runner public IP |
| Modern Chaos | Eight owned Workspaces: Sweden Central, Switzerland North, East US 2, West US 2, North Europe, UK South, Japan East and West Central US; exact application targets discovered, both selectors rejected |
| Removed active topology | Container Apps, registry/image path, Automation Account, Hybrid Workers, lifecycle storage and automatic suspension/scheduling are absent from active templates |

Placement and participation were verified again before the native app case and after database measurement/regional qualification. Actual `zoneRedundant=true`, `maximumNumberOfZones=3` and Boolean `alwaysOn=true` passed direct live guards. Fresh private application/SCM/database DNS and external application/SCM HTTP 403 were verified. These observations remain point-in-time evidence. Resources remain deployed.

## Measurements and individual verdicts

Complete BASE-001 finished at **07:29:16 UTC**:

| Phase | Business operations | Successful canaries | Business success | Successful p95 | Unique writes retained |
| --- | ---: | ---: | ---: | ---: | ---: |
| Five-minute warmup | 6,001 | 301 | 100% | 121 ms | 1,507 |
| Ten-minute baseline | 12,000 | 601 | 100% | 122 ms | 3,006 |
| Twelve-minute load around rejected app execution | 14,401 | 720 | 100% | 123 ms | 3,606 |
| Eighteen-minute native database phase | 21,057 | 1,045 | 97.481598% | 125 ms | 5,354 |

The first three phases had zero failed business operations/canaries and zero scheduled-operation/canary drops. The database phase had **409 failed logical business operations**, **135 dropped scheduled operations**, **10 failed canaries** and **26 dropped canary ticks**. Raw workload HTTP attempts separately include 920 failures; retries and logical operations have different accounting units. Successful-operation p95 excludes failed/dropped operations.

Final complete-history reconciliation passed **16,486 issued/acknowledged measurement writes across six runs**, plus **12 issued/acknowledged private-smoke writes**. Every issued write was resolved and every acknowledged write retained with its expected checksum; acknowledged loss is zero. The rejected app execution caused no established process-crash effect; its healthy-load metrics provide no HA recovery verdict.

Earlier five-minute runs with 1,506 and 1,507 writes are included in that history. Their transient Bastion transfer failures were repaired in place; original evidence was recovered. Completed archives now have explicit bounded transport retries without resubmitting measurement or faults. An exact observer-readiness handshake resolves the separate concurrent SSH startup issue.

| Test | Verdict | Evidence boundary |
| --- | --- | --- |
| BASE-001 | **PASS** | Complete warmup/baseline, all-six-worker/three-zone participation and exact write retention verified |
| HA-APP-001 | **BLOCKED** | Actual accepted execution failed target validation; no successful native Action or independently evidenced process replacement |
| HA-APP-ZONE-001 | **BLOCKED** | Actual selected-zone case returned RequiresAttention/internal resource error before load/fault; mapping and two selected workers remain verified |
| HA-DB-001 | **PASS, reconciled recovery/durability** | Successful native Action, authenticated target operation, actual primary/standby swap, 34.601 s recovery, complete stable window and full-history retention; full-phase availability separately **FAIL** |
| HA-COMBINED-001 | **BLOCKED** | Actual combined-case preflight rejects the application target; no combined fault or disruptive overlap established |
| HA-AZ-001 | **BLOCKED** | No supported correlated real-zone injection/evidence |

Application recovery and combined overlap remain unmeasured because native application injection failed qualification. All required entrypoints were exercised; missing application/combined coverage prevents a complete-suite PASS.

### Native database recovery and independent identity audit

The native failover was accepted at **08:54:09 UTC** and its Succeeded terminal state observed at approximately **09:07 UTC**. The private observer independently established disruption at **08:58:12.3992265 UTC**. Primary/standby changed from zones **1/2 to 2/1** and returned Ready/Healthy.

- Recovery: **34.601 s** to the beginning of a complete qualifying sixty-second window, within the 180-second objective.
- Recovery window **08:58:47-08:59:47 UTC**: 60/60 canaries, 1,200/1,200 business operations, zero drops, p95 **128 ms**.
- Stable window **08:58:47-09:03:47 UTC**: 300/300 canaries, 6,000/6,000 business operations, zero drops, p95 **127 ms**.
- Entire guest phase: **1,097.470 s**, **97.481598%** business success and the errors/drops above. This fails the separate 99.9% full-phase availability threshold.
- Current-run durability: **5,354/5,354** unique writes resolved and retained/checksummed; complete earlier history also passed.

The provider execution's principal metadata differs from the declared Workspace identity. The originally loaded harness therefore reported FAIL after completing load and retention. That original verdict remains unchanged. Current tested completion code reconciled the **same existing execution**, without submitting another fault: exact target, compiled native Action/parameters and successful Action summary passed, and authoritative Activity Log proved the correlated successful PostgreSQL operation's caller and authenticated object claim both match the declared Workspace UAMI. One ordered request start and successful completion share a correlation ID; the start carries a nonempty client-request ID. The successful terminal Activity Log event omits optional HTTP metadata. A failed earlier request and successful retry remain in the raw evidence; the first failure's cause is unestablished.

The metadata discrepancy remains explicitly recorded with its independent identity proof. No role was granted. A separate reconciled verdict records recovery/durability PASS and full-phase availability FAIL; the source harness's initial failure is disclosed. The [specification](specification.md#5-workload-procedure-and-measurements) explicitly separates recovery and full-phase availability.

Load was sequential by case and attributable by unique RunId, with **20 business operations/second plus one canary/second**, at most **200 business VUs + 10 canary VUs** and bounded guest/foreground deadlines. Dropped iterations expose the bounded producer's scheduling saturation during disruption. No processor-specific cause or unlimited concurrency is inferred.

## Linux native-runtime findings

The live regional Kill process schema explicitly describes Linux `dotnet/node` workers. Actual logical/physical mapping was obtained from the approved subscription. The Windows-only Cache Stampede with Process Crash template supplies a documented Windows template-coverage advantage; comparative native runtime/recovery results remain unavailable. See the [OS comparison](research.md#linux-baseline-and-windows-test-coverage).

Distinct provider findings were preserved:

1. Scenario creation rejected an empty `ProcessName` with `Properties.Actions[0].Parameters[0].Value: The Value field is required`, despite successful ARM validation. The explicit `dotnet` process name was revalidated and both deterministic Scenarios/configurations were successfully created.
2. The actual Linux instance-process read endpoint returns `Conflict(The dotnet-monitor tool is not configured to run)`. Completed read-only private container inspection independently found the application, DiagServer and dotnet-monitor processes. The documented monitor-disable setting is absent, and the runtime catalog lists the configured .NET 10 stack as Active. No verified monitor-enable remedy was found.
3. Actual execution and repeated non-fault validation fail with `ScenarioExecutionTargetValidationError`, resource error `-1`, an internal service error and private provider-reference IDs. Fresh discovery and both selectors reproduce the failure through **all eight Workspace locations advertised to this subscription**. The six remaining regional Workspaces each passed exact target discovery before returning RequiresAttention for both selectors. Permission-error arrays are empty; verified roles and successful PostgreSQL execution do not establish the app provider's root cause. These are Workspace-region trials against one Spain Central application; native fault execution was not compared across application hosting regions.
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
| Six remaining regional Workspaces and definitions, including final inventory | 293.790 |
| **Recorded successful stage total** | **4,071.860** |

Separate troubleshooting evidence includes the rejected native-definition attempt (**188.607 s**) and recovered original-write verification (**104.151 s**). The initial baseline attempt's total envelope was **436.205 s**, including its **306.217 s** guest warmup and preflight/transport overhead. Do not add that envelope to its contained measurement as independent time. Regional search, compilation, interactive diagnosis and other foreground checks have separate raw logs; a complete exclusive troubleshooting total was not instrumented.

Complete BASE-001 took **1,403.890 s**, including guest warmup **306.198 s**, guest baseline **610.330 s**, qualification, transfer and retention. The rejected app case took **2,060.966 s**, including its **732.015 s** guest load and **669.368 s** complete-history reconciliation. The database case took **2,664.291 s**, including **1,097.470 s** guest measurement and **974.648 s** full-history reconciliation. Its later identity/effect reconciliation has separate raw evidence.

The Switzerland North postdeployment discovery/validation diagnostic stage took **44.908 s**; the other six regions' discovery and twelve non-fault validations took **342.647 s**. The six-region deployment helper reported approximately **159 s** before its final inventory work; the table uses the complete **293.790 s** stage envelope. These nested or overlapping envelopes must not be added as exclusive wall time. Application recovery/combined-overlap durations do not exist.

## Source validation and continuation

Local fixtures verify deterministic selectors, owned polling, explicit failed/uncertain operations, compiled execution target/identity/parameters, all-selected-worker process replacement, complete post-effect accounting, database role swap, recovery/stability, overlap rejection and retention of every earlier smoke/measurement write. The exact native overlay passed compilation, ARM validation and literal-owned four-resource preview before creation. Release API build and nine API tests passed.

The complete native suite remains **unqualified end-to-end**. The database case is qualified through explicit reconciliation of its real successful execution, effect and retention. All accepted native operations are now reconciled; uncertain future submissions still block another injection. A failed application Action cannot produce a suite PASS. Final history verification revisits earlier run files as well as the current phase.

The active harness synchronizes and checksums all eight private measurement tools before every case and verifies provider non-fault validation before starting load. Validation-specific RequiresAttention cannot become execution success. Signed polling material remains private; accepted/uncertain operations are reconciled before another fault. Provider failures receive separate BLOCKED verdicts. Any subsequent repair must retain exact placement, private paths, the operator-selected Linux platform, recent package/instance-specific baseline and the provider's twenty-minute failover cooldown.

## Remaining resources and manual deletion

The final exact-owned inventory contains **65 ARM-listed entries**: network **26**, workload **29** and operations **10**. This includes eight Workspaces, sixteen private-DNS VNet links and one VM extension; additional nested native definitions, DNS records and roles remain recorded separately in the private manifest. Resources include the six-worker plan/application, private HA database, one private runner, Bastion/NAT/public IPs, VNets/peering, Private Endpoints/DNS, vault/identities/monitoring and modern Chaos definitions. Untagged managed disk/VM-extension entries match exact manifest IDs. The finite public-IP exemption expires at **18:44:21.6507576 UTC, 5 November 2026**.

No automatic deletion, Destroy, Suspend/Resume or purge occurred. The private operator report records exact current group names, profile, expiry, inventory and **unexecuted** deletion commands. When ready, the operator deletes the owned **workload -> operations -> network** groups. Azure-retained vault/backup/audit records can outlive group deletion; no purge or retention-policy change is implied.
