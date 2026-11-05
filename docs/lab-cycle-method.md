# Historical autonomous Container Apps lab cycle method

> **Archived Container Apps procedure.** The commands and operating scope below belong to retired source recoverable from Git. The active [implementation contracts](implementation-contracts.md) and [D22 authorization](../DECISIONS-ACCEPTED.md#d22-autonomous-completion-and-withdrawn-operational-prohibitions) govern autonomous completion of the deployed private App Service/native suite. This archive supplies troubleshooting history.

## Ownership and execution boundary

The earlier run used the operator-selected admin Azure CLI profile and exact ownership checks. Its observed operations covered the isolated lab and temporary exemption described below. Historical execution scope is recorded here; current operating authorization is D22.

Load the approved identity, CLI directory and exact group names from ignored `.local/environment.json`, copied from `config/environment.example.json`. Use `CSL_ENVIRONMENT_FILE` for an alternative private context path. Keep execution plans/validation state in ignored `.azure/` and raw evidence in `.local/`; public reports contain sanitized outcomes only. Run `tests/Test-Publication.ps1` before publishing.

The deployment uses the three dedicated groups and verified region recorded in the private deployment plan. Each new run receives a fresh deployment-instance GUID and a persistent local manifest. New manifests refuse pre-existing groups; continuation uses the original owned manifest. A file lock prevents concurrent local lifecycle commands. Resource IDs are recorded after each deployment, including partially failed deployments. Successful child-resource writes are collected recursively from the explicitly recorded deployment roots because Azure's top-level resource listing omits some child types. Group-scoped policy exemptions are enumerated explicitly. Destruction verifies group ownership and refuses any current resource absent from that inventory.

Record a subscription resource-ID baseline before the first mutation. Compare it after cleanup. Automatic Network Watcher creation can add a regional resource outside the three groups. Retain and report external changes for attribution; the script emits `DESTROYED_SCOPED_WITH_REMAINDER` and withholds a full cleanup verdict. The [first execution report](first-cycle-results.md) documents this observed side effect.

Container Apps can create an Azure-managed infrastructure group as part of the service. Record its name from the environment metadata; allow the service to remove it with the environment. The scripts never issue direct changes or deletions against that managed group.

## Preparation and validation

1. Build the .NET API and run its unit tests.
2. Compile the Bicep modules. Record any missing local schema warnings separately from ARM validation.
3. Run ownership safety (`pwsh .\tests\Test-Ownership.ps1`), simplified topology (`pwsh .\tests\Test-NetworkTopology.ps1`), runner bootstrap semantics (`pwsh .\tests\Test-RunnerBootstrap.ps1`), and synthetic measurement tests from the workspace root. Bootstrap tests execute the installer's actual sed/awk expressions against fixtures in addition to shell syntax checks.
4. Verify the real k6 output format with the format-smoke scenario. k6 1.5.0 exports flattened summary statistics and omits `dropped_iterations` when no iterations are dropped. Raw logging avoids escaping event JSON; only `Point` records count as dropped operations.
5. Complete the `azure-prepare`, `azure-validate`, and `azure-deploy` workflow.
6. Before each deployment, save its ARM `what-if`, check every resource ID against the exact lab boundary, and reject deletion or modification of unowned resources.

### Fail-fast regional and identity prerequisites

Before creating infrastructure, query the exact subscription's PostgreSQL location-capabilities endpoint. Require top-level `restricted: Disabled` and `zoneRedundantHaSupported: Enabled`. An earlier, retired candidate advertised `ZoneRedundant` for the SKU while the top-level HA flag was Disabled; actual creation failed. Current policy follows D20: Italy North first, Sweden Central only when required services are unavailable in Italy North. A supported catalog still requires a successful live create.

Full previews can report Unsupported ARM expressions for identity-dependent administrator/role IDs, including after the identities exist. Preserve the failed preview and keep the exact-ID guard. Validate the independent prerequisite templates, then run `Build-Lab.ps1 -Step Prerequisites -ManifestPath <owned-manifest>`. That stage exports only the five existing identity declarations from the compiled workload/operations modules, with their original location and ownership tags. It creates no app, role assignment or network resource. Verify all five live identities' exact IDs, manifest membership, ownership tags and valid principal GUIDs. Pass the migration, runner and controller principals through `infra/main.bicep`'s `prerequisitePrincipalIds` parameter. This makes administrator/role resource names independent of unresolved `reference()` expressions. Repeat full-stack validation; `Validated build steps` in the ignored plan restricts execution to the currently validated phase. The complete-cycle startup checks every required phase before entering automatic cleanup. Infrastructure creates prerequisites when their two recorded deployment results are absent. On continuation, it reuses all five verified identities, avoiding repeated identity deployments and their full inventory refreshes. An explicit Prerequisites command still redeploys them.

During diagnosis, use staged Build commands with one manifest and retain successful owned resources. Retry only after recording the failure and passing a fresh effective preview. Destroying and recreating an entire Container Apps environment after every failed stage can add substantial provider-side deletion time. The normal unattended cycle retains its automatic cleanup. Deployment and destruction messages include UTC timestamps; inventory refreshes and cloud provisioning/deletion are separate from configured load phases.

Operations provisioning uses the exact already-created migration identity ID, allowing its VMs, NAT and Bastion to progress independently of the workload module. After infrastructure completes, `Initialize-LabMachines` in `scripts/Lab.Common.ps1` runs the three owned VMs' software installations concurrently. Each job independently verifies the approved CLI context and the exact inventoried VM ownership before Run Command. Per-VM JSON is saved beside the manifest. Success requires the installer's final `CSL_INSTALL_COMPLETED` marker, emitted after PowerShell 7.4, k6 and Docker checks; an earlier version string cannot establish completion. A client timeout requires inspecting the existing execution before another install.

The PostgreSQL bootstrap explicitly uses the Ubuntu system CA bundle through `PGSSLROOTCERT=/etc/ssl/certs/ca-certificates.crt` with `PGSSLMODE=verify-full`. This preserves certificate and hostname verification without depending on an operator-created per-user root-certificate file.

In the three Linux VMs, `scripts/runner/install.sh` normalizes `/etc/apt/sources.list` to the canonical Ubuntu archive/security HTTPS endpoints. Rewriting the Azure-specific regional mirror's scheme alone caused TCP timeouts on 443; actual runner HEAD probes verified the canonical alternatives. Rewriting also handles an already-modified HTTPS Azure URL, making retries idempotent. Both apt index updates use `APT::Update::Error-Mode=any` so inaccessible repositories fail explicitly.

In `infra/worker-bootstrap.bicep`, create each Automation Hybrid Worker membership before enabling its VM extension. The initial reverse dependency produced registration 401 responses with zero memberships. Each extension depends on its matching membership and uses the deployment GUID as its force-update tag, enabling repair of the failed initial attempt without reinstalling VM software or rebuilding infrastructure.

An initially failed Linux extension can retain an incomplete local configuration. In this execution, an update then failed with `No section: 'registration-metadata'`. Recovery verified ownership and Failed state of exactly the two `HybridWorkerExtension` resources, removed those extensions, and redeployed the corrected template with the existing memberships. Both extension states and live worker heartbeats must pass before lifecycle execution. Healthy workers and their VMs are retained.

The Runner stage normalizes shell files to UTF-8 without BOM and LF inside the actual transferred archive; `.gitattributes` also requests LF for future Git checkouts. Windows CRLF in the original ZIP caused Bash to reject `set -euo pipefail` before authentication started. The persistent bootstrap regression executes shell text read from the production packaging loop's ZIP and verifies that nonshell bytes remain unchanged.

Failed private bootstrap attempts save their diagnostic tail locally. Only recognized authorization failures receive bounded propagation retries; syntax, packaging, database and other errors stop immediately for diagnosis. The bootstrap result is tracked separately from subsequent log-retrieval exit codes.

The shared CLI wrapper retries only recognized disconnected/reset/aborted transports for read-only commands, at most three attempts with explicit warnings and 2/4-second waits. Mutations and authorization/validation failures remain fail-fast. This handles an observed inventory-read disconnection without repeating a successful deployment. Run `tests/Test-AzureCliTransport.ps1` to exercise this contract without Azure calls.

Azure-provided DNS uses the platform-exempt default path to `168.63.129.16`. Keep custom DNS unset and omit `AzurePlatformDNS` NSG rules: the provider rejected an explicit Allow for that special tag with `SecurityRuleInvalidAccessType`, while a Deny would interrupt required resolution. The general outbound deny continues to cover ordinary traffic. See the [platform IP documentation](https://learn.microsoft.com/azure/virtual-network/what-is-ip-address-168-63-129-16).

Use Azure-allocated Standard static IPv4 for operations NAT and Bastion, following [D13/D14](../DECISIONS-ACCEPTED.md#d14-focused-chaosha-laboratory-networking). The build neither queries nor requires `AllowBringYourOwnPublicIpAddress` registration. Before each deployment, `Assert-LabPublicIpChanges` rejects prefix resources/references, supplied public addresses, non-Standard/static/IPv4 configurations, and effective public-IP `ipTags`. Resource ownership `tags` remain required. Apply an exclusion RG tag only if the applicable rule defines it; the inspected public-IP policy exposes none.

An observed inherited policy appends `FirstPartyUsage=/Unprivileged`, which violates the revised contract. Exact policy identifiers remain in ignored local evidence. The scripts stop before resource deployment and preserve incompatible previews; they never override a policy definition/assignment or register the feature. Dedicated groups can already exist when a group-scoped preview discovers an incompatibility; the cycle cleans up those owned groups. Revalidate policy compatibility before each live cycle.

### User-authorized policy exemption

The operator separately authorized [D15](../DECISIONS-ACCEPTED.md#d15-temporary-lab-only-public-ip-policy-exemption). Inspect the live assignment, initiative and definition first; exempt only the proven incompatible initiative reference. Use the existing approved CLI context. Create an owned network group only after saving the baseline and manifest. At that group scope, create a 24-hour `Waiver` with the exact `policyAssignmentId`, a singleton `policyDefinitionReferenceIds`, a `resourceType` selector for `Microsoft.Network/publicIPAddresses`, and `assignmentScopeValidation: Default`. Keep assignment/reference IDs and request/response files in ignored `.local/policy-exception/`. Creating an exemption requires both exemption-write permission at its scope and `exempt/Action` on the assignment; permission failure stops the operation without PIM or RBAC changes.

Read the exemption back and compare scope, reference, category, expiry, selector and ownership metadata. Preview `infra/modules/network-core.bicep` at the owned network group using the manifest's deployment-instance GUID and `FullResourcePayloads`. Require both IPs, all ten DNS zones, no foreign IDs or modifications/deletions, and passing `Assert-LabPublicIpChanges`. Compare inherited policy snapshots, unrelated exemptions and the resource-ID baseline after the operation.

The initial waiver passed those checks and had expiry **5 November 2026, 07:51:15 UTC**. That preparation initially created only the network group and exemption; the subsequent live attempt and cleanup are recorded in the execution report. Its scope is now destroyed. For a future prepared run, select the matching private environment and, after full validation, continue with its actual owned manifest:

```powershell
pwsh .\scripts\Invoke-LabCycle.ps1 -ManifestPath .\.local\prepared-run\manifest.json
```

Recheck expiry and effective policy before provisioning. Preserve the same ownership manifest and baseline through cleanup. Deleting the owned network group removes its exemption; expiry alone retains the record. Any renewal or broader exception requires separate approval.

The active regional retry has its own new scope, ownership GUID and 24-hour waiver under D16. Read its exact expiry from its live record and ignored manifest. Destroyed manifests remain evidence; they cannot be reused for a new instance.

### Expired or missing exemptions on a later start

Keep required contracts in ignored `.local/environment.json`, in `requiredPolicyExemptions`. Each entry contains the exemption resource `id`, its `assignmentId` and a singleton `referenceIds` array. The same records may also be present as `policyExemptions` in the run manifest. Public configuration examples leave the array empty; supply environment-specific values only in the ignored file.

`Assert-LabPolicyExemptions` reads live Azure state before Build, the complete cycle, operator Resume and every group deployment. Missing groups/exemptions, expired/invalid expiry or changed scope/member/selector stop execution. Expiry within two hours produces a warning. A cycle startup failure occurs outside its cleanup block, so checking an expired waiver cannot delete the existing lab. Destroy remains independent of waiver validity.

When blocked, open **Azure portal > Policy > Exemptions**, select the named exemption under the network lab group, and obtain approval to extend its **Expiration date** (`expiresOn`). If cleanup already deleted that group/exemption, prepare a fresh ownership manifest and group, then create the same narrowly scoped waiver under the new owned scope. Record the approved IDs in the private environment and manifest, repeat GET/expiry/effective-payload verification, and rerun full validation. Keep the environment contract after cleanup as a durable reminder for future starts. No startup command renews or creates a waiver automatically.

Run `pwsh .\tests\Test-PolicyExemptions.ps1` for the offline guard regressions.

The private VM installer selects the newest available `powershell-lts` **7.4.x** package and verifies major/minor 7.4 before reporting success. This keeps the executable behind `powershell_7_4_path` aligned with the Automation 7.4 runtime when repositories also offer a newer LTS. Missing 7.4 packages fail explicitly; no different runtime is silently substituted.

The subscription-scope validation wrapper previews creation of the three groups and the same infrastructure before any group exists. Machine-readable stage previews use `--no-pretty-print`; a successful Azure response may contain `error: null`.

Passing a public-IP preview certifies the evaluated lab IPs only. Service-owned Container Apps provisioning can still fail an internal Network feature check. Regional PostgreSQL capability catalogs can advertise HA while an actual subscription offer rejects multi-zone creation. Preserve exact provider errors, stop without weakening HA or registering excluded features, inventory partial resources and run owned cleanup. A complete live verdict requires successful provider creation and measured private tests.

## Private bootstrap

Provision two directly peered VNets, operations NAT/Bastion, private endpoints, private DNS links, dedicated Container Apps environment, PostgreSQL HA server, private telemetry, registry, secrets vault, control storage, Automation account, and private VMs. Container Apps uses managed egress; the private VM subnet uses explicit NAT egress. Standard NAT is a single-zone management dependency.

VM Run Command installs the runner software through the controlled outbound path. Ubuntu package sources use HTTPS. Workers use PowerShell 7.4 LTS and a matching Automation runtime environment; the `powershell_7_4_path` environment variable is installed before Hybrid Worker onboarding. A temporary Bastion tunnel carries SSH and source transfer into the private runner. No runner VM receives a public IP. PostgreSQL access uses a migration managed identity; a database role maps the runtime identity's object ID through `pgaadauth_create_principal_with_oid`. The runtime receives only connection, schema usage, table read, and insert permissions.

Generate a deployment token in the private runner and store it in the private vault. Container Apps references the secret using its runtime identity. The runner acquires the token at test time and clears the process variable afterward. No secret value belongs in source code, the manifest, or test reports.

Build and push the application image from the private runner. Deploy the app by its immutable digest with six minimum replicas, twelve maximum replicas, explicit health probes, and an identity-authenticated private database connection. The environment has public network access disabled; app-level external ingress allows private-endpoint clients to reach it.

## Test protocol

- **Readiness and privacy:** verify distinct PostgreSQL HA zones, environment zone redundancy, at least six app replicas, private successful requests, and rejection from the operator's Internet path.
- **Warmup:** run the configured workload for five minutes.
- **Baseline:** run 20 business operations per second for ten minutes, with an 80/20 read/write mix and a separate one-second canary. Require the baseline business success and successful-operation latency thresholds. Reuse operation IDs during retries and reconcile checksums.
- **Database failover:** start a twelve-minute private load phase, wait one minute, execute the exact-target Chaos scenario configuration, and save the execution result and observed PostgreSQL roles/zones. Do not substitute an arbitrary target or a scale-down simulation.
- **Recovery:** evaluate raw events against independent action evidence. Require a complete 60-second window, exactly one canary tick per second, the configured business-operation denominator including drops, at least 99% canary/business success, successful-operation p95 at most one second, and recovery within 180 seconds.

A full-phase failover success rate can decrease during an injection while the post-injection recovery objective still passes. Record both results separately. Missing injection or observation evidence produces an inconclusive or blocked result. `HA-AZ-001` remains blocked without a supported real-zone injection and evidence tying that zone to the affected application path.

The private Log Analytics query in `scripts/runner/telemetry.ps1` uses `union withsource=SourceTable` and summarizes by `SourceTable`. Container system events have their own severity-valued `Type` column; grouping that column misclassified real `Normal`/`Warning` events as missing system telemetry. Query the selected lab workspace from the private runner with its managed identity. This correction requires no diagnostic-setting, public-access or RBAC changes.

The Bastion tunnel must pass an authenticated SSH `true` command before private stages begin. A local TCP listener alone can remain reachable while the backend resets or stalls during banner exchange. Shared SSH/SCP options disable prompts, bound connection attempts to 20 seconds, and detect unresponsive established sessions. Readiness retries are bounded, while authentication and host-key failures stop immediately.

Failover load dispatch changes directory before detaching a `nohup sh -c` wrapper and redirects all standard streams. The wrapper records its PID and exit status; an existing live PID blocks overlap. The operator checks that the workload remains alive before fault submission. Backgrounding an entire `cd ... && ...` list can hold SSH output open until workload completion and invalidate injection timing; the executable dispatch regression guards this exact failure.

Before starting failover load, `scripts/Test-Lab.ps1` verifies that the Chaos workspace's `properties.scopes` contains only the exact owned workload resource group. Its identity has Reader on that group for discovery and Contributor only on the PostgreSQL server for execution. The Scenario configuration must include exactly that server. The operator invokes the pinned Workspace `discover` operation, waits for success, then checks the paginated discovered-resource list contains the exact target once. A successful discovery status alone can describe an empty snapshot. Provider failures retain their original error codes.

Use the canonical service-direct action `urn:csci:microsoft:azurepostgresql:failover/1.0.0` and the single-server include. The action definition omits the external-custom-runbook resource field. Require terminal native success, exactly one target and independent before/after PostgreSQL zone/HA observations.

Preserve ISO offsets and fractional seconds when reading evidence. PowerShell JSON conversion can materialize a timestamp as `DateTime`; normalize that typed value directly to UTC before further parsing. Formatting it as an ordinary string loses its offset. The corrected evaluator and timezone regression exercise this boundary.

After recovery passes, re-read every unique write issued by that run through the authenticated private API. `tests/load/evaluate-durability.ps1` deduplicates retries, checks original operation IDs/checksums, requires all acknowledged writes retained, and resolves unacknowledged writes to an existing matching row or confirmed absence. Missing acknowledged rows, changed payloads, conflicting evidence and transport failures prevent a pass. Resume repeats this check against the same original run. Verdicts are saved separately for failover and resume.

Runner results are compressed before Bastion transfer and extracted locally into the existing evidence layout. Copying all uncompressed historical metrics on every phase caused multi-minute transfer delays. Compression preserves raw event/metric files and their contents. Failed-stage retrieval labels snapshots taken while files are still being written.

The verified regional action catalog exposes `FailoverMode` as an integer enum: `0` is planned failover and `1` is forced failover. The Scenario key/value wire representation therefore supplies `"1"`, with `RestoreOnStop` and `SkipIneligibleServers` both `"false"`. The semantic test remains the approved forced failover.

## Lifecycle control

After private readiness verification, persist the readiness timestamp and a suspension deadline exactly 24 hours later in private Blob Storage. Publish the REST-based lifecycle runbook to the private Automation account and bind it to the private Hybrid Worker group. Verify the one-time deadline schedule and hourly reconciliation schedule.

Use `runbookType: PowerShell` with the explicit `csl-ps74` runtime environment; the API rejects combining that environment with `PowerShell72`. Manual jobs and schedule links share one versioned `ContextBase64` parameter containing the exact context and intent. This avoids observed Linux Hybrid Worker multi-parameter misbinding. Decoding validates scope before identity or Azure access.

Schedule creation requests use ownership-derived IDs in a versioned `csl-lifecycle-context-v1` namespace. Azure can return a different association ID; re-registration finds the exact schedule/runbook pair, validates its actual ID belongs to the owned account, and fetches full details because list responses omit parameter values. It verifies worker/context and reuses that association. Ambiguous or drifted associations fail explicitly. When migrating the original development-only seven-parameter signature, capture and remove only its verified owned legacy bindings before registering the new context. Keep the new namespace: an observed deleted legacy ID returned create Conflict despite GET NotFound.

Azure Automation truncates start times to a full minute. Round the one-time start upward to the first full UTC minute at or after the exact persisted deadline, then verify the returned enabled schedule and its offset in `[0, 60)` seconds. An early rounded-down trigger would find an unexpired lease and return without suspending. The state deadline remains unchanged; dispatch and resource-stop latency are separate. Run `tests/Test-ControllerRegistration.ps1` for the production request, stable-link and minute-boundary regressions.

The controller acquires a Blob lease, validates group ownership, and records desired state before changing runtime resources. Suspension deactivates app revisions, stops PostgreSQL, lowers Dedicated capacity where supported, and deallocates the ordinary runner. Private workers and their management dependencies remain available. Resume restores runtime resources and requires a fresh private baseline before a new deadline is armed.

The shared runbook ARM helper sets JSON media type even for bodyless actions. Default form content type was rejected by the Container Apps deactivation endpoint. PostgreSQL waits report observed state changes with UTC timestamps, separating provider stop/start time from worker dispatch.

The operator additionally polls actual PostgreSQL state, runner power state, active revision count and configured Dedicated minimum after a lifecycle job completes, while checking unchanged private access and cross-zone HA. Configured Dedicated minimum is recorded separately from an observed allocated-node count. `Invoke-LabCycle.ps1 -IncludeLifecycleSmoke` opts into Reconcile/Suspend/Resume after the load/failover phases; ordinary cycles preserve their existing shorter phase sequence.

After Resume, retrieve the fresh private baseline, verification and durability records with the same shared compressed-evidence helper used by workload phases. Preserve them locally before teardown removes the runner.

The real disconnected 24-hour soak is a separate test. An ordinary first-cycle run cannot establish that outcome from schedule creation alone.

## Cleanup and retained evidence

Stop the local tunnel and disable lifecycle schedules and active jobs using the structured ARM helper with explicit JSON media type; avoid inline native-shell JSON for those mutations. Verify the current inventory against the manifest, then delete the **workload, operations, and network** groups in that order. Operations NAT/Bastion reference public IPs in the network group and must release those dependencies before network deletion. Purge only the recoverable vault whose original ID matches the owned vault. Re-query the three exact groups and record customer-controlled cleanup results. Azure Activity Log, billing/audit records, and service-managed deletion retention can persist according to platform requirements.

Keep the manifest, deployment/what-if responses, software versions, raw events, summaries, action evidence, and recovery verdict locally. Record actual results and limitations in the final run report. A partial deployment failure must still pass ownership-safe cleanup; it must not be reported as a successful resilience test.

## Repeatable commands

Use PowerShell 7 with Azure CLI, Bicep, .NET 10, OpenSSH, and the approved CLI profile. Validate the deployment plan before invoking cloud execution.

```powershell
pwsh .\scripts\Invoke-LabCycle.ps1 -IncludeLifecycleSmoke
```

The cycle creates a fresh manifest, builds the private lab, tests it, and invokes manifest-scoped cleanup even when a required stage fails. The switch includes Reconcile/Suspend/Resume, observed resource postconditions and original-write retention; omit it for the shorter sequence. Individual build/test/destroy commands are also available for diagnosis. Supply the exact manifest path when continuing an interrupted run:

```powershell
pwsh .\scripts\Build-Lab.ps1 -Step Infrastructure -ManifestPath .\.local\<cycle>\manifest.json
pwsh .\scripts\Test-Lab.ps1 -ManifestPath .\.local\<cycle>\manifest.json -Phase baseline
pwsh .\scripts\Destroy-Lab.ps1 -ManifestPath .\.local\<cycle>\manifest.json -Confirm:$false
```

Private runner stages require an active Bastion tunnel on the configured local port. Destroy can run through Azure management APIs without that tunnel.
