# First Azure lab execution: method and results

Date: 4 November 2026. All execution timestamps below are UTC.

This archived Container Apps result records the earlier run's actions and scope. Current operating authorization is [D22](../DECISIONS-ACCEPTED.md#d22-autonomous-completion-and-withdrawn-operational-prohibitions), with active [implementation contracts](implementation-contracts.md).

This report starts with the latest measured results, followed by the chronological original failures and their corrections. Environment identifiers and full raw evidence remain in ignored local files.

**Platform and coverage boundary:** this report records the earlier **Container Apps/PostgreSQL** cycle. Native App Service faults, application placement across three observed zones, the planned application-capacity test and the combined test were not qualified. The [current App Service specification](specification.md) supplies their new requirements. Final group deletion was handed to the operator; no independent final cleanup or purge certification is claimed here.

## Latest verified results

The Sweden Central retry provisioned the complete private, zone-redundant stack and executed a genuine Chaos Studio PostgreSQL forced failover against exactly one owned server. Public access remained disabled; the primary moved from zone 1 to zone 2 and the standby to zone 1, with HA Healthy.

| Check | Measured result |
| --- | --- |
| Private application integration | PASS: DNS, readiness, authentication, durable create/read, checksum, idempotent replay and payload conflict |
| Full five-minute warmup | PASS: 6,001 successful operations, zero failures/drops, p95 29 ms |
| Full ten-minute baseline | PASS: 12,001 successful operations, zero failures/drops, p95 27 ms; 601 successful canaries |
| Genuine Chaos action | PASS: one PostgreSQL target, action Succeeded, independently observed primary/standby swap |
| Recovery objective, maximum 180 seconds | PASS: **38.624 seconds** from evidenced action start to the qualifying window |
| Recovery window | 13:43:12-13:44:12 UTC: 60/60 canaries, 1,199/1,200 successful business operations, one accounted drop, p95 20 ms |
| Injected phase, full twelve-minute availability | 97.118% business success, p95 56 ms; its stricter full-phase 99.9% availability gate is FAIL, recorded independently of recovery |
| Post-fault durability | PASS: all 3,558 acknowledged unique writes retained with matching checksums, including 340 acknowledged before action start; zero acknowledged loss |
| Suspend resource postconditions | PASS: PostgreSQL Stopped, runner deallocated, zero active revisions, configured D4 minimum zero; HA/private configuration preserved |
| Resume resource postconditions | PASS: PostgreSQL Ready/Healthy, runner running, six replicas in one Healthy/Provisioned revision, D4 minimum three |
| Post-resume durability | PASS: the same 3,558 acknowledged writes retained with exact checksums; zero acknowledged loss |
| Resumed controller and private baseline | PASS: two native registrations left exactly two verified associations; each sixty-second baseline passed with 1,201 operations, zero failures/drops and p95 56/57 ms |
| Exact teardown and external inventory | Manual group deletion handed to the operator; final cleanup/purge remains unverified in this report |

The first successful fault run retained its complete raw events. A local timestamp-parsing error was corrected and the same events were reevaluated; another database disruption was unnecessary.

The [regional chronology](#regional-retry-and-timing-diagnosis) separates provisioning, troubleshooting, measurement and provider deletion time. [Development readiness](development-readiness.md) distinguishes this bounded cycle from the full-zone, combined-fault, cancellation and disconnected-soak acceptance still required.

## Original feature-gate attempt: historical outcome

The implementation, local tests, Azure ARM validation, and deployment previews completed. Real provisioning encountered a subscription-level feature gate on the two Standard public IPs. An equivalent API-version retry reached the same error.

The three dedicated lab groups were removed and their absence verified. An automatic regional Network Watcher remained outside those groups. That original attempt ended **BLOCKED**, before application/load/failover measurement. Later successful measurements appear above.

Subsequent specification revision: [D13](../DECISIONS-ACCEPTED.md#d13-azure-allocated-public-ips-without-byoip) explicitly excludes BYOIP and removes the feature-registration prerequisite. Read-only inspection identified an inherited policy adding `FirstPartyUsage=/Unprivileged` to both public-IP payloads. The current blocker is that policy's incompatibility with the revised allocation contract. This revision performed no resource deployment or governance change.

## Original attempt: boundary and configuration

- Subscription, tenant and approved operator: recorded only in ignored local configuration; active subscription Owner verified.
- Region: an earlier, retired regional candidate. Original geography remains in ignored raw evidence; current deployment policy follows D20.
- Deployment instance and exact network/workload/operations group names: recorded in the ignored local ownership manifest.
- Direct resource mutations were restricted to those three groups. No PIM, feature registration, policy modification, quota increase, or price/budget checks were performed during this execution.

The diagrams and their explanatory walkthrough are in the [architecture guide](architecture-guide.md). The [cycle method](lab-cycle-method.md) describes the intended private build, measurements, controller, and destruction. This report records the subset actually executed.

## Original attempt: verified results

| Check | Result | Evidence and scope |
|---|---|---|
| CLI identity and subscription Owner | PASS | Approved CLI profile; active Owner at the exact subscription |
| Bicep compilation | PASS | Main, application, and validation wrapper compile |
| Azure ARM validation and what-if | PASS | Official validation helper: 21 creates, 0 modifies, 0 deletes |
| API unit tests | PASS | 9/9 tests; application logic only |
| Ownership and preview guards | PASS | Foreign IDs/manifests, unknown modifications, deletion, machine-readable output, and `error: null` |
| Synthetic load/recovery tests | PASS | Accounting, redaction, drops, complete windows, exact 99% boundary, and verdict handling |
| Real k6 1.5.0 format checks | PASS | Actual executable; flat summaries, zero-drop omission, raw event logging, tagged drop points |
| Network provisioning | FAIL | Both Standard public IPs rejected by a subscription feature gate |
| Private API, migration, image publication, and telemetry | BLOCKED | Workload and runner provisioning were not reached |
| Cloud warmup/baseline and PostgreSQL failover | BLOCKED | No live business workload or Chaos execution |
| Controller and suspend/resume | BLOCKED | Implemented scripts; private worker execution unverified |
| Real-zone HA-AZ-001 | BLOCKED | Supported correlated real-zone injection/evidence still required |
| Deletion of the three dedicated groups | PASS | Thirteen inventoried resource IDs removed; all three groups absent |
| Preservation of baseline resource IDs | PASS | All 21 baseline IDs remain |
| Full subscription cleanup | BLOCKED | One automatic Network Watcher retained outside the allowed mutation scope |
| Original feature-state preflight | Historical PASS; superseded | It rejected before group creation. D13 replaces it with effective-payload validation and removes feature registration as a prerequisite. |

These results describe the original attempt. Later regional retries supply the live application evidence.

## Execution sequence

1. Recorded the pre-existing subscription resource inventory: 21 resource IDs.
2. Completed local checks and the `azure-validate` workflow. The subscription-scope wrapper previewed the new groups and the same group-scoped infrastructure before creation.
3. Created the three dedicated tagged groups and issued guarded resource-group what-if.
4. Corrected two incompatibilities exposed by the real CLI response: machine-readable what-if requires `--no-pretty-print`, and a successful response can contain `error: null`. Regression tests cover both.
5. Issued the infrastructure deployment. Network resources were partially created, but both public-IP writes failed.
6. Retried equivalent Standard IP definitions using API `2023-09-01` after the original `2024-05-01` definitions. The same feature error persisted.
7. Corrected child-resource inventory: the successful firewall policy rule collection was absent from the top-level resource list. Recorded deployment roots now drive recursive successful-operation inventory.
8. Preserved deployment-operation evidence, deleted the dedicated workload/network/operations groups, and verified their absence.
9. Compared the subscription inventory and exported the mutation audit. All baseline IDs remained; the automatic regional Network Watcher was the additional resource.
10. Removed the temporary SSH private/public key files. No tunnel, private test process, Chaos execution, or controller job had been started.

The manifest began at `2026-11-03T23:56:50Z`. Final scoped isolation verification completed at `2026-11-04T00:21:57Z`.

## Public-IP feature gate

Azure returned:

```text
SubscriptionNotRegisteredForFeature
Microsoft.Network/AllowBringYourOwnPublicIpAddress
```

Affected objects, both within the dedicated network group:

- `pip-csl-hub-firewall`
- `pip-csl-hub-bastion`

The templates requested Azure-allocated Standard static IPs. They supplied no custom IP address or custom prefix. Subsequent read-only inspection found a governance-induced payload difference, detailed below.

The original read-only feature lookup confirmed `NotRegistered`. D13 excludes registering or depending on this feature. Its registration state is no longer a deployment prerequisite.

The historical feature lookup and original/retry deployment correlation IDs are retained only in ignored local evidence. Current scripts do not query or register that feature.

### Subsequent finding: inherited IP-tag append policy

The saved `csl-infrastructure.what-if.json` shows this effective property on both public IPs, although it was absent from the source templates:

```json
"ipTags": [
  { "ipTagType": "FirstPartyUsage", "tag": "/Unprivileged" }
]
```

Read-only ARM queries identified the source:

| Scope/object | Exact location |
| --- | --- |
| Management group | Exact scope retained in ignored local policy evidence |
| Policy assignment, initiative and reference | Exact identifiers retained in ignored local policy evidence |
| Policy definition and display name | Environment-specific identifiers omitted from this public report |
| Effect and property | `append` to `Microsoft.Network/publicIPAddresses/ipTags[*]` |

The rule applies to public IPs lacking that exact tag and has no parameters. Empty or omitted `ipTags` still match its condition. This explains the divergence between the Azure-allocated source declaration and the effective request. The association with the observed feature error is supported by the preview and deployment failures; no internal Network provider feature-check trace is available.

Apply any separately authorized governance resolution at this exact management-group assignment/initiative reference, or as an appropriately scoped exemption for the lab. The scripts do not create exemptions or modify policies. No compatible live provisioning result has yet been obtained.

The revised implementation retains firewall/Bastion, explicitly requests Standard static IPv4, and rejects tagged/prefix-based/supplied-address payloads before resource deployment. A registered feature cannot relax this contract. This revision preserves private connectivity and enterprise egress requirements.

### D13 revision verification

On 4 November 2026, the revised network and main Bicep compiled. Exact compiled-resource checks found two Standard static IPv4 public-IP declarations, no prefix resources, and no literal address/prefix/IP-tag inputs. Ownership/public-IP regression tests and changed PowerShell parser checks passed.

The official read-only validation helper passed CLI, authentication, compilation, Azure ARM validation, and what-if, again reporting 21 creates, zero modifies, and zero deletes. A fresh full-payload preview completed at `05:56:31Z` and still included the policy-appended tag on both public IPs. The new contract guard rejected that effective payload. Azure policy compatibility remains **BLOCKED**; the revised plan has not been certified as Validated.

Evidence is in [the BYOIP-free revision directory](../.local/byoip-free-revision/): `validation.log`, `effective-what-if.json`, `public-ip-append-policy.json`, and `validation-result.json`. All three dedicated groups remained absent. No resource deployment, feature registration, policy change, or external-remnant deletion was performed. Ephemeral validation keys and parameter files were removed.

## Actual cleanup and external remnant

The owned inventory contained the hub VNet, firewall policy, its child rule collection, and ten private DNS zones. All thirteen resource IDs belonged to the exact network group. The workload and operations groups had no deployed workload services.

Final checks confirmed:

- All three dedicated groups: absent.
- Baseline resource IDs: 21/21 preserved.
- Final resource inventory: 22 IDs.
- Vault: never created; no purge required.
- Container Apps infrastructure group: never created.
- Manifest: `DESTROYED_SCOPED_WITH_REMAINDER`.

The additional resource is a platform-created regional Network Watcher outside the three dedicated groups. Its exact ID is retained in the ignored local cleanup manifest and mutation audit.

The mutation audit records platform-principal writes to `NetworkWatcherRG` and this regional watcher while the lab network was provisioned. Its first successful write was at `00:01:31Z`, followed by another successful write at `00:11:29Z`. The watcher was absent from the baseline. No VNet remained in the final subscription listing.

The scripts retained this resource because it lies outside the authorized direct-write boundary. Its retention reflects the scope safeguard; it has a separately resolvable cleanup requirement. Any cleanup decision must target this exact new watcher in `NetworkWatcherRG`, preserve other resources and existing group contents, and use the baseline/audit evidence for attribution.

Resource-ID comparison establishes presence and absence. The mutation audit supplements that comparison; no full pre/post configuration snapshot was taken.

## Evidence locations

Persistent evidence is under [the current-cycle directory](../.local/current-cycle/):

- `manifest.json`: instance identity, owned IDs, deployment roots, failure, and scoped cleanup.
- `validation.log`: official ARM validation/what-if result.
- `csl-infrastructure.what-if.json`: machine-readable stage preview.
- `network-deployment-operations.json`: Azure operation-level failure evidence.
- `infrastructure-build.log` and `infrastructure-retry-stable-api.log`: failed execution records.
- `destroy.log`: scoped deletion and external-inventory warning.
- `preexisting-resources.json` and `postcleanup-resources.json`: baseline and final resource inventory.
- `activity-mutation-audit.json`: direct and platform-side write/delete/action records.
- `final-isolation-verification.json`: separate dedicated-group, baseline-ID, and full-cleanup verdicts.

Failed root deployments returned no successful outputs. No cloud raw workload or recovery report exists because those phases were never reached.

## Readiness and repeatability

The specifications remain sufficient for development. The current implementation provides the private infrastructure, bootstrap, API, deterministic measurement, scoped lifecycle, and destruction entry points.

Remaining execution work:

1. Resolve inherited public-IP append-policy compatibility through separately authorized governance action, or approve a compatible deployment target. Keep BYOIP and feature registration excluded.
2. Decide the authorized treatment of the automatic external watcher and related service side effects.
3. Revalidate, deploy a fresh instance, and prove private image publication, migration, API identity/privacy, and telemetry.
4. Execute the five-minute warmup, ten-minute baseline, twelve-minute supported failover, and independent recovery evaluation.
5. Verify Hybrid Worker onboarding and actual controller/suspend/resume behavior. A disconnected 24-hour soak has its own evidence requirement.
6. Verify complete cleanup and external side-effect attribution. Preserve HA-AZ-001's separate real-zone evidence gate.

After prerequisites are resolved:

```powershell
pwsh .\scripts\Invoke-LabCycle.ps1
```

The script uses a fresh manifest path, rejects existing groups and effective public-IP payloads conflicting with D13, runs the private stages, and invokes scoped destruction on failure. Group-scoped validation can encounter the policy conflict after the dedicated groups have been created; the cycle cleans up those owned groups. External inventory changes produce an explicit incomplete-cleanup result.

## D14 follow-up: simplified network and policy-tag attempt

Verified at **4 November 2026, 06:15:35 UTC**. The first deployment/cleanup described above remains historical evidence.

### Changes made

Removed Azure Firewall, its policy/rules, firewall subnet/address, separate hub VNet, custom DNS proxy, firewall-directed route tables and hub peerings. The lab now uses two directly peered VNets, Azure-provided DNS with private-zone links to both, operations Bastion, and explicit Standard NAT egress for private VMs. Container Apps keeps managed egress and private service access.

The two remaining NAT/Bastion public IPs are declared in the dedicated network group, where the effective preview can resolve them independently of service-module outputs. NAT/Bastion resources remain with operations. Standard NAT is a single-zone management egress dependency; no new full-zone management-HA claim is made.

### Exact policy inspection

An inherited management-group public-IP append policy was identified. Exact management-group, definition, assignment, initiative and reference identifiers are retained only in ignored local evidence.

The condition checks resource type and whether `properties.ipTags` already contains `FirstPartyUsage=/Unprivileged`. If absent, the append action adds it. The rule contains **no resource-group tag exclusion**. The assignment exposes no exclusion parameter, override, selector or `notScopes`; the initiative entry also exposes no exclusion parameter. Ordinary configured RG metadata is not referenced by this rule.

There was therefore no rule-defined RG exclusion tag to apply. No guessed tag, exemption, policy modification or BYOIP registration was used.

### Bounded attempt and results

| Check | Result |
| --- | --- |
| Simplified Bicep compilation and topology contracts | PASS |
| Ownership and effective public-IP contract regressions | PASS |
| Changed PowerShell parsing | PASS |
| Official CLI/authentication/build/ARM-validation helper | Core PASS |
| ARM what-if | 16 evaluated creates, zero modifies/deletes; dependent service modules short-circuited |
| Effective NAT/Bastion addresses | Both still receive `FirstPartyUsage=/Unprivileged` |
| D13 policy compatibility | BLOCKED; guard stops before provisioning |
| Resource groups created | None; all three names remain absent |
| Resource inventory before/after | Same 22 IDs, including the previously retained watcher |
| Live workload, Chaos and lifecycle tests | Not run |

The preview is an evaluated subset because ARM cannot resolve some module-output references before deployment. An earlier simplified preview also omitted the public IPs when they were inside operations; the declarations were moved into the independently evaluable network module and both adjusted payloads were then verified. Core PASS does not certify complete nested-resource validation or live feasibility.

Updated English specifications, accepted D14, operating guide, method, and editable architecture/lifecycle diagrams accompany the implementation. Local evidence is under `.local/firewall-free-revision/`; ephemeral validation parameters/SSH keys/generated template were removed. The official validation workflow remains blocked, and no further deployment/destruction was needed for this read-only attempt.

## Public-source preparation and fresh restart attempt

Verified at **4 November 2026, 07:33:28 UTC**.

Subscription/tenant IDs, the approved account, authentication-profile directory and exact group names now live in ignored `.local/environment.json`. The public `config/environment.example.json` has empty identity/scope fields. Operator scripts and Bicep receive the same explicit context; account, ownership and lab-only deletion checks remain enforced. Lifecycle jobs pass the configured subscription and three group names to the runbook.

The deployment plan and validation state are excluded under `.azure/`. Raw evidence, original environment-specific reports, manifests and private keys remain under ignored `.local/`. Public reports omit real environment identifiers, policy names and correlation IDs. The repository has not been initialized or published.

Publication checks passed against 71 candidate files using actual Git ignore semantics. Regression tests verified rejection of a leaked configured identifier, an unexpected real subscription path and an already-tracked private file. Ownership, parameterized topology/lifecycle scope, PowerShell parsing and synthetic load/recovery tests also passed.

The original lab groups were absent, so a restart required fresh provisioning. The official read-only Azure helper passed CLI/authentication/build/ARM-validation and returned 16 evaluated creates, zero modifies/deletes. The nested-service short-circuit limitations still apply.

The new full-payload preview again added `FirstPartyUsage=/Unprivileged` to both NAT/Bastion public IPs. The unchanged D13 gate stopped before provisioning. **The requested live end-to-end cycle remains BLOCKED and was not executed.** All three groups remain absent; before/after inventories contain the same 22 resource IDs. No policy change, feature registration, unrelated mutation or additional cleanup was performed.

Raw retry evidence is under ignored `.local/public-source-retry/`. Temporary validation parameters, SSH keys and the generated validation template were removed. A passing core helper does not certify the blocked deployment as Validated.

## User-authorized scoped policy exemption

Verified at **4 November 2026, 07:53:56 UTC**.

The operator explicitly requested an exception for the blocking policy. Direct inspection reconfirmed one proven blocker in the current region: the inherited initiative member appending `FirstPartyUsage=/Unprivileged` to public IPs. The subscription-level assignment listing omitted that inherited assignment; a direct management-group ARM GET verified it. No additional policy was exempted without evidence of a current blocking effect.

Created one owned network resource group and one temporary `Waiver`. Its scope is that group only, its `policyDefinitionReferenceIds` contains only the incompatible append member, and its selector includes only `Microsoft.Network/publicIPAddresses`. Assignment-scope validation remains `Default`. The waiver expires at **5 November 2026, 07:51:15 UTC**; no automatic renewal is configured.

| Verification | Observed result |
| --- | --- |
| Exemption GET | Exact scope, single reference, category, expiry, ownership metadata and public-IP selector matched |
| Full-payload network what-if | 12 creates: ten private DNS zones and both NAT/Bastion public IPs; zero modifies/deletes |
| D13 public-IP gate | PASS for both effective payloads; zero effective IP tags |
| Inherited assignment and definition | Unchanged against saved pre-operation snapshots |
| Existing unrelated exemptions | All six unchanged; exactly one new lab exemption |
| Subscription resource-ID baseline | All 22 retained; generic resource listing still contains 22 |
| Explicit lab exemption inventory | One owned exemption recorded, supplementing generic resource listing |
| Workload and operations groups | Absent |
| Live infrastructure/application tests | Not run during this exemption operation |

The first CLI attempt stopped on a locally serialized singleton selector object before creating an exemption. The owned empty group and original manifest were retained. JSON serialization was corrected to preserve root arrays, regression-tested for zero/one/multiple elements, and the same owned operation was resumed successfully.

The proven public-IP **preview** incompatibility is resolved for the waiver window. Actual resource-provider provisioning, other service constraints, complete validation, private bootstrap, load/failover and lifecycle results remain unverified. The preparation leaves the owned network group and exemption available for continuation with `.local/policy-exception/manifest.json`; use that manifest for subsequent build or cleanup.

Raw assignment/definition snapshots, existing-exemption comparison, baseline, creation/GET responses, preview, safety checks and manifest remain in ignored `.local/policy-exception/`. Public files contain no actual policy, account or subscription identifiers. The accepted [D15 decision](../DECISIONS-ACCEPTED.md#d15-temporary-lab-only-public-ip-policy-exemption) records the limited authorization.

## Guarded live-cycle execution after the exemption

Executed on **4 November 2026** using the original owned preparation manifest.

### Startup protection and validation

The ignored environment now retains `requiredPolicyExemptions` independently of disposable run manifests. Build, the complete-cycle command and operator Resume check live exemption state before mutations; every group deployment repeats the check. Missing/expired records or an unexpected assignment/member/category/selector produce a blocking message naming the exemption and group and directing an approved create-or-extend action. A waiver expiring within two hours produces a warning. No command renews it automatically.

Offline tests cover active, expired, missing, invalid-expiry, missing-property, near-expiry, contract-drift and manifest-only records. Integration tests invoke the actual Build/cycle/Resume entry points with an expired waiver and assert **zero Azure writes, unchanged manifest and no lock/cleanup**. Destroy remains usable after expiry.

The official validation workflow completed before provisioning. Its core helper passed CLI/authentication/compile/ARM validation/what-if and reported 15 evaluated creates, zero modifies/deletes. The separately fetched full-payload preview returned 14 creates and one unchanged network group; both public-IP payloads passed D13. Dependent modules still had short-circuited coverage. The API Release build passed with zero warnings/errors and unit tests passed 9/9. Dockerfile/context checks passed; actual image construction was staged for the private runner because local Docker was unavailable.

### Actual Azure outcomes

| Stage | Result | Evidence and limits |
| --- | --- | --- |
| Waiver startup gate | PASS | Existing finite, narrowly scoped exemption read and verified |
| Network core | PASS | Ten private DNS zones and both NAT/Bastion public IPs created |
| Real public-IP contract | PASS | Both Standard static IPv4 resources reached Succeeded with zero IP tags |
| PostgreSQL zone-redundant HA | BLOCKED | Create returned `MultiAzHaIsOfferRestricted`; catalog availability did not guarantee this offer's provisioning eligibility |
| Container Apps environment | BLOCKED | Internal provisioning returned `SubscriptionNotRegisteredForFeature` for the excluded Network BYOIP feature |
| Key Vault initial create | FAIL, corrected | API rejected explicit `enablePurgeProtection: false`; source now omits it |
| Corrected Key Vault create | PASS | Independently deployed from the corrected source; GET verified ownership, disabled public access and unenabled purge protection |
| Monitor private endpoint | FAIL, mitigation unverified | Provider returned InternalServerError; source now waits for both AMPLS scoped-resource associations; compilation/contract tests pass |
| Operations VMs and private bootstrap | BLOCKED | Dependent workload deployment failed before these stages |
| Image, API readiness, private load and failover | NOT RUN | Infrastructure prerequisites were unavailable |
| Suspend/resume and real-zone loss | NOT RUN | No runnable application; no HA claim |

The exemption resolved the original declared-public-IP blocker. Container Apps' failure occurred in service-owned internal provisioning. The observed managed infrastructure group was inspected read-only; its internal IP request was unavailable, so the exact policy/provider attribution remains unproven. The lab-scoped waiver does not establish compatibility of service-owned resources outside that group.

At that stage PostgreSQL's provider response suggested a service/subscription-limits request or a different region. Subsequent capability diagnosis identified a viable regional retry, described below; no operator support request was required to try it. HA was preserved and no feature was registered. Container Apps additionally needs a proven compatible service-owned network path within the approved governance boundary. The original attempt ended before an end-to-end application test.

### Cleanup and evidence

The failed deployment was allowed to reach a terminal state, then its actual resource IDs were inventoried. Cleanup uses only the existing manifest and exact dedicated groups, including the temporary exemption and the separately verified vault. Service-managed infrastructure is left to Container Apps deletion.

Raw validation, operation errors, real IP GET responses, vault verification, manifest and cleanup logs remain in ignored `.local/policy-exception/`. Cleanup verification is recorded below after the owned groups and recoverable objects have been checked.

## Regional retry and timing diagnosis

### Why the preceding attempt took so long

| Phase | Observed UTC interval | Interpretation |
| --- | --- | --- |
| Infrastructure | 08:04:24-08:11:36, about 7 minutes | Actual provider provisioning, ending in terminal errors |
| Diagnosis/inventory/vault correction | After the failed infrastructure stage | Explicit troubleshooting and ownership capture |
| Owned cleanup | 08:17:27-08:52:07, about 35 minutes | Container Apps asynchronous deletion dominated; its state was ScheduledForDelete during the wait |
| Independent final verification | 09:00:20 | Exact groups and service-managed group absent, vault purged, 22 baseline IDs preserved |
| Private load/Chaos/lifecycle tests | Not started in that attempt | Their configured durations contributed no runtime |

Two waiting helpers reached their deadlines while the service-side deletion continued. A timeout meant verification had not yet completed; it did not cancel Azure deletion or establish a terminal cleanup failure. No overlapping deletion was submitted. The main cleanup ultimately completed with `DESTROYED` and `PURGED`.

The final verifier confirmed all six unrelated exemptions unchanged and the original lab waiver removed. It explicitly accounted for the new, independently owned regional-retry waiver. A real invocation of the complete-cycle entry point after cleanup stopped on the missing original waiver, emitted create-or-extend guidance, and recreated no group. Environment-specific evidence is retained in ignored `final-cycle-verification.json`.

### Corrected PostgreSQL eligibility check

The retired regional candidate's location-capabilities response had `restricted: Disabled` but **`zoneRedundantHaSupported: Disabled`**. Its selected SKU still listed `ZoneRedundant`; that SKU-level value was insufficient to establish this subscription's eligibility. The startup guard now checks the top-level flags before infrastructure creation. This historical finding does not describe the current Italy North capability response.

Sweden Central, UK South and Switzerland North reported HA Enabled. Sweden Central also listed the exact required SKU/zones and PostgreSQL failover Action, so the autonomous retry uses new dedicated Sweden Central groups with the same private topology and HA requirements. No HA downgrade, quota/support request, public access or feature registration was used.

### Staged retry method and verified preparation

The new run has a fresh ownership GUID, evidence directory and 24-hour waiver for the same single public-IP policy member at its new network-group scope. A full live snapshot records the short overlap with the old cleanup; only exact already-inventoried previous-lab IDs were excluded from the retry comparison baseline. All other current resources were preserved.

Official core CLI/auth/Bicep/ARM validation and what-if passed, reporting 90 creates and zero modifies/deletes. The independent full-payload preview contained 89 creates, two unchanged groups and seven Unsupported identity-dependent expressions. The unchanged ownership guard rejected those unresolved IDs. This is a staged-validation prerequisite, with preserved diagnostics.

Exact-source identity prerequisites and the PostgreSQL resource were independently ARM-validated and previewed: three workload identities, two operations identities and one zone-redundant server, all literal owned IDs and create-only changes. Both effective public-IP payloads and the live finite waiver passed. API Release build and 9/9 tests, regional/identity/waiver/ownership/topology/publication/parser checks passed.

A full-preview retry after identity creation still reported the same seven Unsupported expressions. ARM what-if left `reference()` principal values unresolved despite real identities being present. The correction resolves the three relevant live principal IDs, verifies exact owned/inventoried identities and GUIDs, and explicitly parameterizes administrator/role resource-ID calculations. Regression tests cover invalid principals, foreign ownership, unrecorded identities, parameter propagation and actual startup preservation when only a bounded phase is validated. The guard also rejects Unsupported changes with literal IDs.

The first live retry creates the exact compiled PostgreSQL resource and requires Ready, Healthy ZoneRedundant in distinct zones with public/password access Disabled. Identity bootstrap makes principal IDs available; full-stack validation must then repeat before the remaining deployment. Actual provisioning results are recorded as they become available. A successful preview provides no runtime/HA verdict.

The targeted PostgreSQL deployment completed at **09:16:35 UTC**, about 13 minutes after its preview began. Live verification passed: **Ready**, **Healthy ZoneRedundant**, distinct primary/standby zones, public network access Disabled, password authentication Disabled, and the expected ownership tag. The regional retry therefore overcame the original PostgreSQL eligibility failure without operator intervention or weakened HA. This establishes infrastructure availability; failover recovery and application data integrity still require the live workload tests.

The Container Apps retry selects an internal environment with public network access Disabled and the same private endpoint and zone redundancy. Application ingress remains `external: true` for private VNet clients. Service management/outbound public IPs can still exist.

Complete-stack validation passed at **09:33:42 UTC** with explicit verified principal parameters: **89 Create, one owned PostgreSQL Modify, eight NoChange, zero resource deletions and zero Unsupported IDs**. Both public IPs passed the effective-payload gate. The PostgreSQL modification contains omitted provider-returned default/read-only storage/encryption/replica fields. The official helper's textual +/- counters include property differences; resource-level JSON counts establish the actual boundary.

### Container Apps provisioning and Private Link correction

The main deployment began at **09:42:52 UTC**. The internal Container Apps environment reached **Succeeded**, independently observed at **09:50:20 UTC**, without registering the excluded feature or changing policy on its service-managed group. The Monitor private endpoint also succeeded with the corrected scoped-resource dependencies.

The deployment then stopped at the Container Apps private endpoint: `InvalidGroupId`. The source used singular `managedEnvironment`; the live environment's `privateLinkResources` endpoint advertised plural **`managedEnvironments`**, including its required member and regional private DNS zone. The private endpoint was never created, so no deletion was required. The source and a compiled-template regression were corrected against that live provider contract.

The dependency graph also unnecessarily serialized all operations infrastructure behind the complete workload module merely to retrieve a migration identity ID. Operations now receives the exact ID of the independently created, ownership-verified prerequisite identity. A regression verifies that operations no longer depends on completion of the workload deployment. This permits parallel provisioning without shortening measurement windows or weakening ownership checks. Successful services are retained while the corrected stack is validated and retried.

### Operations NSG correction and avoidable orchestration time

The corrected deployment began its main provisioning at **10:07:50 UTC**. The Container Apps Private Link connection accepted the plural group ID and reported **Approved**, **Auto Approved**, and connection state **Succeeded** at **10:17:04 UTC**; the endpoint itself was still Updating, so completion remained unclaimed.

Independent operations provisioning exposed `SecurityRuleInvalidAccessType`: explicit Allow was rejected where only Deny was accepted. The operations NSG contained an Allow rule for `AzurePlatformDNS`. Microsoft's platform-IP documentation explains that normal Azure DNS communication bypasses NSGs unless explicitly targeted with this special tag. The correction removes that rule, preserving required default DNS and the ordinary outbound deny. No policy exemption or platform feature is needed for this correction.

The repeated identity stages also contributed measurable orchestration overhead: previews began at **10:00:08 UTC**, while the main deployment began at **10:07:50 UTC**. The roughly eight-minute interval included two identity redeployments and recursive safety inventories. Infrastructure continuation now reuses the recorded prerequisite stages after checking all five live identities for exact ID, manifest membership, ownership and valid GUIDs. Fifteen negative regression cases cover invalid, foreign and unrecorded versions of each identity. VM installations are also parallelized across the three independently verified targets. Configured load windows remain unchanged.

At **10:22:05 UTC**, independent GETs confirmed **Succeeded** for the complete workload module and the Container Apps private endpoint. The root deployment's sole terminal failure was the operations NSG. The private endpoint correction therefore has real provisioning proof; the earlier Updating observation was transient. Existing workload resources remain available for the next guarded operations retry.

### Complete infrastructure and software-bootstrap semantics

The next Infrastructure command reused the five verified identities at **10:26:05 UTC** and began actual main provisioning at **10:27:06 UTC**. The complete infrastructure reached **Succeeded** at **10:39:31 UTC**. The repaired operations NSG succeeded; the remaining observed provider wait was Bastion provisioning. About one minute preceded the main deployment, compared with about eight minutes in the previous continuation. No successful workload service was destroyed to obtain this result.

Parallel VM installations began at **10:43:26 UTC**. Their first native actions all completed around **10:44 UTC**, with Run Command reporting `ProvisioningState/succeeded` while the shell had failed on its first sed expression. Its `|` delimiter collided with regex alternation. The final completion marker correctly rejected these responses; native extension provisioning alone would have produced a false success.

The installer now uses a separate `#` delimiter and escaped hostname dots. A new persistent bootstrap regression executes the exact source sed command against Ubuntu archive/security and unrelated-host examples, executes its actual mixed-version PowerShell package selector, and checks strict PostgreSQL TLS and terminal-marker semantics. All pass. The three failure responses were preserved before retrying only VM initialization, leaving the completed infrastructure intact.

The next attempt exposed a separate network dependency: the Azure-specific Ubuntu mirror timed out on HTTPS. Canonical Ubuntu archive/security, Microsoft packages and GitHub all returned **HTTP 200 from the private runner**, proving that required NAT/HTTPS connectivity worked. The installer now replaces the mirror hostname with the canonical HTTPS archive, handles already-rewritten URLs, and makes apt index errors fatal. The semantic regression verifies idempotent rewriting.

All three concurrent VM installations passed at **11:00:08 UTC**, after starting at **10:56:24 UTC**. The success marker follows actual PowerShell 7.4, k6 and Docker checks. Software initialization therefore has real VM evidence; private image construction remains a later stage.

### Hybrid Worker registration dependency

The first worker-bootstrap deployment began at **11:03:41 UTC**. Both Linux extensions failed registration with **401**. Independent control-plane inspection found **zero worker memberships**: the template incorrectly waited for successful extension enable before creating those memberships.

The repair reverses that dependency, creating both memberships before enabling their respective extensions. A force-update tag based on the ownership GUID causes the failed configurations to enable again. A compiled-template regression verifies both dependency directions. Official targeted validation passed at **11:11:41 UTC**, with two membership creates, two owned extension modifications, and zero deletions or Unsupported changes. Successful infrastructure and installed software are retained for the retry.

The first update created both memberships but exposed partially initialized guest state from the original failure: `No section: 'registration-metadata'`. Ownership and Failed state were checked for exactly the two extensions. Removing and reinstalling those extensions with the corrected template succeeded at **11:24:05 UTC**; independent reads verified both extensions Succeeded and both workers sending heartbeats. Their VMs and installed software were retained.

A subsequent inventory read encountered Azure CLI `RemoteDisconnected` after the deployment had succeeded. This was classified as a client transport failure. A new regression proves bounded, explicitly warned retries for read-only disconnected/reset/aborted requests, with no automatic mutation retries.

### Private source transfer and bootstrap

The first private SSH/source transfer worked. The archived Bash script still contained Windows CRLF, causing `set -euo pipefail` to fail before any authentication. The actual transferred archive contained 44 carriage returns and 44 line feeds in that script. Packaging now normalizes shell entries to BOM-free UTF-8/LF, and the production archive loop is tested by executing its extracted shell content while verifying nonshell byte preservation. Future Git checkouts also request LF through `.gitattributes`.

The original generic propagation retry would repeat unrelated bootstrap failures. It now saves each diagnostic tail, retries recognized authorization failures only, and tracks bootstrap success independently of log retrieval. Actual loop tests cover immediate success, authorization recovery/exhaustion, and immediate rejection of a Bash failure.

The corrected private bootstrap started at **11:34:02 UTC**. By **11:37 UTC**, it had completed the identity-authenticated database setup and reached the image's .NET restore step. Image publication, application verification and test results are recorded separately after their respective runtime gates.

The Runner stage completed at **11:40:23 UTC**, with an immutable digest recorded. Application deployment completed at **11:42:31 UTC**; private verification and the stage completed at **11:44:27 UTC**. Actual checks passed for private-endpoint DNS, readiness, unauthenticated business-request rejection, durable creation, idempotent replay, read-after-write checksum and different-payload conflict. The successful bootstrap log and digest remain in ignored evidence.

### Controller API and schedule precision

The private 60-second pre-controller workload passed. The runbook API rejected `PowerShell72` combined with an explicit PowerShell 7.4 runtime environment; `runbookType: PowerShell` is required. The corrected registration also uses stable ownership-derived schedule-link IDs, enumerates existing links and rejects parameter drift. Its production-loop regression verifies initial creation, repeat registration without duplicate links, and distinct owner IDs.

The next live read exposed Automation's minute-precision start times: a requested deadline with **36.4869505 fractional seconds into the minute** was returned at second zero, **36.4869505 seconds early**. The previous subsecond equality check correctly rejected that configuration. An early one-time `Reconcile` could otherwise run before expiry and do nothing.

The persisted deadline remains exactly readiness plus 24 hours. Registration now rounds only the schedule upward to the first full minute at or after that deadline and verifies a returned offset of at least zero and less than 60 seconds. Exact-minute, fractional-second and final-tick boundary regressions pass. This adds an explicit service-granularity contract; worker dispatch and stop/start durations remain separately measured.

Controller registration completed successfully at **12:00:32 UTC**. The first full warmup ran for **305.588 seconds including its completion work**, configured for five minutes at 20 operations/second. It recorded **6,001 successful business operations, zero failed operations, 100% success, p95 29 ms, and zero dropped workload/canary samples**.

The following monitoring gate exposed a query-classification error. Real system events were returned under `Normal` and `Warning` because the query grouped their severity-valued `Type` column. Application requests were already present. The correction uses `union withsource=SourceTable` and groups by that provenance column. The private re-query passed at **12:23:26 UTC**, counting **18,298 application requests and 183 container system events**. No monitoring permissions, public access or diagnostic configuration changed. The original complete five-minute workload was retained; baseline continuation did not repeat it.

A separate tunnel delay was reproduced: the local Bastion port accepted TCP while SSH banner exchange reset or stalled. Unbounded SCP was stopped, its process tree was identified, and bounded SSH probes isolated the backend issue. Shared SSH/SCP options now disable prompts, limit connection attempts and detect lost sessions. A fresh tunnel passed authenticated readiness after one bounded banner-timeout retry. Baseline began at **12:23:32 UTC**.

The full ten-minute baseline passed: **12,001 successful business operations, zero failures, 100% success, p95 27 ms, 601 successful one-second canary ticks, and no dropped operations or canaries**. Its measured interval was **12:24:01–12:34:11 UTC** (609.527 seconds including completion work).

The first failover dispatch then revealed a separate shell-precedence defect. Backgrounding `cd ... && (...) &` left an outer shell holding SSH output descriptors while the twelve-minute workload ran. A scoped process inspection confirmed the exact outer shell, child PowerShell and k6 processes. The held SSH command was stopped before the operator could submit a late injection. That unfaulted workload is excluded from Chaos acceptance evidence.

Dispatch now changes directory first and detaches the entire `nohup sh -c` wrapper with all standard streams redirected. It records a PID and fresh exit marker, rejects an overlapping invocation, and verifies the workload is still running before submitting a fault. An executable regression runs the actual production shell command with a timed fixture, verifies output channels close before completion, verifies the final exit code, and rejects a concurrent second dispatch. The successful baseline and warmup are preserved for the retry.

The corrected dispatch returned promptly. Its first Scenario execution failed before injection with **`ResourceDiscoveryNotReadyError`**: a Workspace discovery snapshot is mandatory. The initial isolation error was clarified to preserve the actual provider error. A scoped discovery at **12:53:28–12:53:32 UTC** succeeded, with the Workspace scope independently checked to contain only the lab PostgreSQL server. The production preflight now performs and verifies discovery before starting load; executable branch tests cover success, foreign scope, missing polling address and provider failure. This failed Scenario run produced no accepted failover result.

The next run exposed **`ScenarioPlanNoActionsError`**, again before injection. A successful discovery over a single-resource scope had produced no actionable target. The Workspace discovery scope was corrected to the exact owned workload resource group, and its identity received Reader on that group. Execution permission remains Contributor on the single PostgreSQL resource, with a single-server Scenario include filter.

The two-resource correction passed official source-derived Bicep compilation, ARM validation and literal-ID preview: **one owned Workspace modification, one group-scoped Reader create, 24 Ignore, zero Delete/Unsupported**. Guarded deployment completed at **13:18:43 UTC**. A fresh discovery at **13:21 UTC** exposed 25 owned-group rows including exactly one PostgreSQL server with the expected canonical ID. Production now verifies that actual target presence before starting load.

Failure diagnostics also measured **241.8 MiB** of local raw result files while a repeated uncompressed historical transfer consumed several minutes. Results are now compressed before transfer and extracted into the same local layout. The transfer optimization preserves every raw record and keeps partial-snapshot warnings explicit.

### Successful native PostgreSQL failover

The discovered target initially remained skipped in the compiled Scenario plan. The corrected service-direct definition uses canonical action ID `urn:csci:microsoft:azurepostgresql:failover/1.0.0`, removes the custom-runbook `externalResource` field, and retains only the exact PostgreSQL resource include. Official source-derived compilation, ARM validation and literal-ID preview passed; the guarded correction deployed at **13:35:20 UTC**.

The genuine twelve-minute load ran **13:41:26-13:53:37 UTC**, including completion work. The native action started at **13:42:33.376 UTC** and completed successfully at **13:48:53.336 UTC**. Its inventory contained exactly one PostgreSQL resource. Before/after control-plane reads verified primary **1 -> 2**, standby **2 -> 1**, private access disabled and Healthy HA. Native action completion took about six minutes twenty seconds; business recovery was established earlier by raw application observations.

The full injected phase recorded **13,986 successful and 273 failed business operations, 142 dropped workload operations, 691 successful and ten failed canaries, and 20 dropped canary operations**. The full-period success was **97.118%**, with successful-operation p95 **56 ms**. Its phase-level 99.9% gate correctly failed during the injected outage.

The separate recovery verdict passed in **38.624 seconds**. Its complete sixty-second window contained **60 successful canaries**, **1,199 successful business operations out of 1,200 scheduled**, **one explicitly included drop**, and successful-operation p95 **20 ms**. Recovery acceptance retains the approved 99% window threshold and 180-second objective.

Initial evaluation was inconclusive because `ConvertFrom-Json` materialized an offset timestamp as a local `DateTime`. Converting it to a culture-formatted string discarded its offset and fractional precision, moving the evidence one hour beyond the actual workload. The evaluator now preserves typed timestamps as full UTC ISO instants before parsing. Positive/negative/half-hour offsets and fractional-second regressions pass. Reevaluating the preserved original events produced the measured result above.

### Native lifecycle parameter transport

The first actual Hybrid Worker Reconcile failed its scope guard. Instrumented native output showed the storage name bound to the subscription parameter and the controller client ID bound to a resource-group parameter. Saved job input and published metadata contained the correct named values. The guard prevented any resource mutation.

Lifecycle requests and schedules now carry one deterministic, versioned Base64/JSON context parameter. The runbook decodes and validates the subscription, three distinct groups, storage, identity and intent before authentication. This removes multi-argument ordering from worker transport while preserving exact scope checks. Native Reconcile completed at **14:07:28 UTC**. Production-code regressions reject malformed context, wrong schema, invalid scope, duplicate groups and unsupported intents.

Live Automation association reads also exposed server-assigned IDs and omitted parameters in the list projection. Re-registration now identifies the single exact schedule/runbook association within its owned account, reads its full detail and verifies worker and context before reuse. Tests model the real server-assigned IDs and incomplete list response. The two legacy bindings from the earlier runbook signature were captured and removed only within the independently verified, inventoried, tagged lab Automation account.

### Whole-run durability and bodyless ARM actions

The post-fault private audit completed at **14:17:32 UTC**. It re-read every unique issued write from the genuine fault journal and verified **3,558 retained acknowledged writes with exact checksums**, including **340 acknowledged before action start**. No acknowledged row was lost, no checksum changed and no issued write remained unresolved. Repeated attempts were deduplicated by operation ID.

That first full audit took about four minutes forty seconds, including private verification and transport. The repeatable verifier now reuses one HTTP session instead of repeatedly establishing connections. The post-resume audit exercises the same original-write set with that corrected implementation.

The first Suspend request then exposed `UnsupportedMediaType`: bodyless PowerShell POSTs defaulted to `application/x-www-form-urlencoded`, which the Container Apps action API rejects. The runbook's shared ARM helper now declares `application/json` for both bodyless actions and explicit payloads. Its production-function regression covers both forms. Only Suspend/Resume were retried; successful load, fault and durability evidence were preserved.

Suspend then passed: request stage **14:21:16 UTC**, native job Completed **14:27:27 UTC**, and all independent resource postconditions verified **14:27:49 UTC**. PostgreSQL was Stopped, the ordinary runner deallocated, active app revisions zero and the configured D4 minimum zero. The allocated-node count was not separately measured. Management workers, NAT/Bastion and private control dependencies remained available.

Resume began **14:27:49 UTC**. Its native job completed **14:36:32 UTC**; independent checks converged at **14:40:01 UTC**. PostgreSQL was Ready/Healthy with primary zone 2 and standby zone 1, the runner running, six replicas in one Healthy/Provisioned revision, and D4 minimum three. Public access and zone-redundancy settings remained unchanged. This separates about nine minutes of provider restoration from the additional revision/capacity convergence.

Controller re-registration subsequently encountered a deleted legacy job-schedule ID that returned Conflict on creation despite NotFound on GET and an empty association list. The atomic-context transport now has its own ownership-derived `context-v1` association namespace, avoiding reuse of the deleted seven-parameter signature's IDs. A regression explicitly rejects reuse of that legacy namespace. Controller verification was retried against the already resumed resources; another stop/start was unnecessary.

### Completed Resume qualification

The two final controller registrations ran **14:44:39-14:48:33 UTC** and **14:48:33-14:52:25 UTC**. Both completed, preserving exactly two schedule associations. Native detail reads verified the exact private worker group and the single expected context parameter on each association. The second registration reused the live logical associations without creating duplicates.

Their sixty-second private baselines each completed **1,201 successful business operations**, with zero failures or dropped workload/canary samples. Successful-operation p95 was **56 ms** and **57 ms**. These short post-resume checks supplement the earlier full five-/ten-minute measurements.

The optimized post-resume audit ran **14:52:25-14:52:54 UTC**, including private verification and retrieval. All **3,558** original acknowledged writes still existed with correct checksums. Reusing the HTTP session reduced this end-to-end check to about **28 seconds**, compared with about **four minutes fifty seconds** including retrieval on the initial implementation.

Full raw results, including the fresh baselines, private smoke checks, native fault and both durability verdicts, were retrieved before deletion. The final compressed archive was **34.55 MiB**; compression/retrieval/extraction completed in about fifty seconds. The final owned RBAC audit recorded twelve assignments, including the bounded discovery Reader permission.

### Final teardown method

Cleanup started after the measured database and lifecycle checks passed; application-capacity, combined and real-zone tests remained unqualified. Before actual group deletion, a Windows CLI inline-JSON schedule update reached Azure without a supported JSON media type and was rejected. The historical cleanup implementation uses the shared structured ARM transport with explicit JSON content type for schedule/job mutations; tests execute that transport against both bodyless actions and structured payloads. Runtime tests were preserved and cleanup alone was retried.

The dependency order is **workload -> operations -> network**. Operations NAT/Bastion reference public IPs in the network group, so those consumers must be removed first. A compiled-topology regression guards this cross-group order. The operator reissued group deletion and subsequently took responsibility for its verification; background observation was stopped at the operator's request. Final deletion, recoverable-vault purge, unrelated-resource comparison and exemption comparison remain uncertified in this report.

### Interpreting run time

| Work | Measured contribution and overlap |
| --- | --- |
| Final successful main infrastructure deployment | 10:27:06-10:39:31 UTC, about 12 minutes 25 seconds; follows earlier staged region/identity/provider corrections |
| Concurrent VM software initialization | 10:56:24-11:00:08 UTC, about 3 minutes 44 seconds |
| Private database/image bootstrap | 11:34:02-11:40:23 UTC, about 6 minutes 21 seconds |
| Required measured load | Five-minute warmup + ten-minute baseline + twelve-minute injected phase: **27 configured minutes**, plus bounded completion work |
| Native Chaos completion | About 6 minutes 20 seconds, overlapping the twelve-minute load; measured business recovery was 38.624 seconds |
| Native Suspend plus observed checks | About 6 minutes 33 seconds |
| Native Resume plus revision/capacity convergence | About 12 minutes 12 seconds before the private/controller verification |
| Two final registration checks | About 3 minutes 54 seconds and 3 minutes 52 seconds, each including a one-minute baseline and recursive inventory/API work |
| Corrected post-resume durability audit | About 28 seconds for 3,558 writes; earlier non-reusing implementation took about 4 minutes 50 seconds including retrieval |
| Final complete evidence transfer | About fifty seconds for the compressed archive |
| Provider deletion | Recorded separately; the earlier failed-region attempt required about 35 minutes |

This was a first qualification with staged troubleshooting and retained successful resources. Regional/provider-contract corrections, rejected previews, bounded unfaulted failed-attempt workloads and transport repairs account for additional elapsed time. The corrected repeatable scripts incorporate those repairs. A second fresh, uninterrupted full cycle has not been measured. Future total time still depends on regional capacity, provider creation/deletion, the requested lifecycle option and safety inventories. The approved load windows were preserved throughout.
