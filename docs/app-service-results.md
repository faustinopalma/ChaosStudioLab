# Private Linux App Service execution results

Evidence date: 4 November 2026, UTC.

## Outcome

The corrected private architecture is deployed. Actual six-worker participation across three physical availability zones, private SCM publication and native definition creation passed their individual gates. The complete deterministic suite is **BLOCKED**.

At 23:06:28 UTC an external principal submitted `Microsoft.DBforPostgreSQL/flexibleServers/stop/action` against the owned database. Its subsequent state is `Stopped`. The actor differs from the approved deployment operator and the Workspace execution identity; its purpose has not been established. No native fault was submitted by this run. The operator's no-Resume boundary was preserved when explicit restart authorization could not be obtained. No inherited governance, expiry, exemption selector or unrelated resource was changed.

Another workload region would leave this external-stop cause unresolved. Investigation and authorization for the existing stopped database are required before continuing its baseline and native tests.

## Deployed and observed capabilities

| Gate | Actual evidence |
| --- | --- |
| Linux plan | Spain Central, P1v3, six workers, `reserved=true`, `zoneRedundant=true`, `maximumNumberOfZones=3`, `perSiteScaling=false` |
| Three physical zones | Six actual instance IDs; two workers each in `spaincentral-az1`, `spaincentral-az2`, `spaincentral-az3` |
| Application participation | Every worker served successful live health and authenticated checksum-verified business reads |
| Private ingress/publication | Approved application Private Endpoint, separate outbound Integration subnet, private application/SCM DNS, successful checksummed private SCM publication |
| Public application/SCM | Actual external requests returned HTTP 403; public application access is Disabled |
| Private PostgreSQL | Public access Disabled; private authenticated reads/writes succeeded; initially Ready/Healthy zone-redundant HA with primary zone 1 and standby zone 2 |
| Management | One private runner in Sweden Central, global VNet peering, existing Bastion path; no runner public IP |
| Modern Chaos | Sweden Central Workspace discovered the exact Spain Central application/database; PostgreSQL and deterministic exact-instance/zone process definitions are deployed |
| Removed active topology | Container Apps, registry/image path, Automation Account, Hybrid Workers, lifecycle storage and automatic suspension/scheduling are absent from active templates |

Placement and application participation are point-in-time observations before the external database stop. Subsequent dependency readiness is blocked. The application and single runner remain running; resources remain deployed.

## Measurements and individual verdicts

The real five-minute warmup completed 6,001 business operations and 300 one-second canary ticks:

- Business success: **100%**; failed business operations: **0**.
- Successful-operation p95: **124 ms**.
- Failed canaries, dropped business operations and dropped canaries: **0**.
- **1,506 unique issued writes reconciled**, with exact checksums and no acknowledged loss.
- Guest measurement envelope: **306.217 seconds**, including k6 setup/completion overhead.

The first evidence-collection attempt failed on a Bastion SSH banner-exchange timeout. Its guest measurement had succeeded. The private tunnel was re-established in place and the original evidence and writes were recovered; no lab redeployment or manually simulated fault followed.

| Test | Verdict | Evidence boundary |
| --- | --- | --- |
| BASE-001 | **BLOCKED** | Warmup passed; the required ten-minute baseline was prevented by the external database stop |
| HA-APP-001 | **BLOCKED** | Healthy database and complete baseline prerequisites fail; exact-instance native effect remains unqualified |
| HA-APP-ZONE-001 | **BLOCKED** | Placement/mapping and definition are verified; baseline/database prerequisites prevent native zone-effect execution |
| HA-DB-001 | **BLOCKED** | Database is externally Stopped; no forced failover submitted |
| HA-COMBINED-001 | **BLOCKED** | No qualified baseline, database readiness or independently observed overlapping native effects |
| HA-AZ-001 | **BLOCKED** | No supported correlated real-zone injection/evidence |

Recovery, fault-phase availability and final post-fault retention remain unmeasured. The 1,506-write PASS was obtained before the external stop; retention after that stop requires a fresh verification once authorized readiness is restored. No data loss is inferred from inability to read a stopped server.

## Linux native-runtime findings

The live regional Kill process schema explicitly describes Linux `dotnet/node` workers. Actual logical/physical mapping was obtained from the approved subscription. The Windows-only Cache Stampede with Process Crash template supplies a documented Windows template-coverage advantage; comparative native runtime/recovery results remain unavailable. See the [OS comparison](research.md#linux-baseline-and-windows-test-coverage).

Two separate provider findings were preserved:

1. Scenario creation rejected an empty `ProcessName` with `Properties.Actions[0].Parameters[0].Value: The Value field is required`, despite successful ARM validation. The explicit `dotnet` process name was revalidated and both deterministic Scenarios/configurations were successfully created.
2. The actual Linux instance-process read endpoint returns `Conflict(The dotnet-monitor tool is not configured to run)`, including after successful private publication. Native Action execution has not occurred, so this remains an unresolved runtime diagnostic dependency. No guessed enable setting, Windows switch, public SCM fallback or manual process termination was applied.

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
| **Recorded successful stage total** | **3,335.685** |

Separate troubleshooting evidence includes the rejected native-definition attempt (**188.607 s**) and recovered original-write verification (**104.151 s**). The initial baseline attempt's total envelope was **436.205 s**, including its **306.217 s** guest warmup and preflight/transport overhead. Do not add that envelope to its contained measurement as independent time. Regional search, compilation, interactive diagnosis and other foreground checks have separate raw logs; a complete exclusive troubleshooting total was not instrumented.

No ten-minute baseline, native recovery or combined-overlap measurement duration exists.

## Source validation and continuation

Local fixtures verify deterministic selectors, owned polling, explicit failed/uncertain operations, compiled execution target/identity/parameters, all-selected-worker process replacement, complete post-effect accounting, database role swap, recovery/stability, overlap rejection and retention of every earlier smoke/measurement write. The exact native overlay passed compilation, ARM validation and literal-owned four-resource preview before creation. Release API build and nine API tests passed.

The native harness remains **unqualified end-to-end**. It preserves an unresolved accepted submission and blocks another injection until reconciled. A failed runtime Action cannot produce a suite PASS. Final history verification revisits earlier run files as well as the current phase.

To continue, use the existing ignored manifest and approved private environment/profile. Establish the external stop's source, obtain explicit authorization for any required database start, restore verified Ready/Healthy private HA, then rerun the complete baseline before individually selected native tests. Preserve the twenty-minute failover cooldown and exact actual-placement gates. Do not recreate the owned scope, renew the finite exemption automatically or run historical controllers.

## Remaining resources and manual deletion

The final owned inventory contains **58 top-level ARM resources**: 26 in the network group, 22 in workload and 10 in operations. Child resources and role assignments are also retained in the private manifest. Resources include the six-worker plan/application, stopped private HA database, one running private VM, Bastion/NAT/public IPs, VNets/peering, Private Endpoints/DNS, vault/identities/monitoring and modern Chaos definitions. The finite public-IP exemption remains within its original expiry.

No automatic deletion, Destroy, Suspend/Resume or purge occurred. The private operator report records exact current group names, profile, expiry, inventory and **unexecuted** deletion commands. When ready, the operator deletes the owned **workload -> operations -> network** groups. Azure-retained vault/backup/audit records can outlive group deletion; no purge or retention-policy change is implied.
