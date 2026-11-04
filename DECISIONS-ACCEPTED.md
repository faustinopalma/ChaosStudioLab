# Accepted design decisions

**Current controlling amendment: [D17-D19](#d17-private-azure-app-service-across-three-zones).** The target is private Linux Azure App Service across three observed zones, retained PostgreSQL HA, modern Chaos Studio and PC-driven deployment with manual deletion. The [current specification](docs/specification.md) defines its acceptance gates.

D01-D16 retain the previous design record. D17-D19 supersede their conflicting Container Apps, worker-capacity, replica-adapter, controller, automated lifecycle and regional-certification provisions. Historical execution results remain attached to their original platform. The source refactor and App Service deployment have not yet been performed.

## D17. Private Azure App Service across three zones

The target application platform is **Linux Azure App Service**, using a Web App and an App Service Plan. The operator selected Linux over the earlier Windows-first proposal. Verify the supported Linux runtime, private publication and native Action compatibility. A blocked fault does not authorize an automatic OS switch, classic-mode fallback or custom-runbook replacement.

Document any evidenced Windows test-coverage advantage in the [OS comparison](docs/research.md#linux-baseline-and-windows-test-coverage). The documented Windows-only process-crash template is a specific limitation; the available evidence does not establish a general Windows-only restriction for every native App Service Action.

The application must operate across three distinct observed physical availability zones. Require `properties.zoneRedundant = true` and `properties.maximumNumberOfZones >= 3` on the actual plan, together with the actual Web App instance inventory, health and traffic evidence from all three zones. A region's zone count and a configured worker count are insufficient. Preserve the earlier six-worker baseline, disable per-app scaling for this single-app lab and start with fixed capacity.

Verify the actual plan's scale-unit capability early. Refresh per-instance `physicalZone` evidence before each fault and after recovery. Missing placement evidence or a two-zone plan blocks readiness. Do not silently downgrade the three-zone requirement.

Provide both outbound regional VNet Integration through a subnet delegated to `Microsoft.Web/serverFarms` and inbound Web App Private Endpoint. Use separate integration/private-endpoint subnets and private DNS for the application and SCM/Kudu. Disable public data-plane access. Retain private PostgreSQL zone-redundant HA and its distinct primary/standby zones.

Retain the proven workload/operations VNet topology, one private runner and required management connectivity initially. Remove the Container Apps environment, Dedicated D4 profile, registry/image-pull path and their unused endpoints. Historical Container Apps results provide no App Service or three-zone application qualification.

## D18. Local deployment and operator-managed deletion

Run deployment orchestration from the PC with bounded steps, visible console progress and local logs. Use the private runner for publication, migrations and probes that need private network access. Disclose buffered output instead of describing it as live streaming.

Remove the Automation Account, two Hybrid Worker VMs, lifecycle control store, automatic 24-hour suspension, Suspend/Resume workflow and random-chaos controller. The operator explicitly starts tests and manually deletes the dedicated groups. Deployment failure preserves owned resources and returns an explicit error; it never triggers automatic faults or deletion.

Preserve ownership manifests, private-context checks, effective-policy previews and manual missing/expired-exemption guidance. Show deletion dependencies and recoverable-object/retention limitations to the operator. There is no independent expiry enforcement when the PC disconnects.

This decision supersedes the older automatic lifecycle, control-store, unattended-campaign and scripted-destruction requirements. Existing lifecycle scripts and diagrams remain historical implementation artifacts until refactored or retired.

## D19. Modern native Chaos and bounded evidence

Use Chaos Studio Workspaces, Scenarios and Actions, with the documented preview limitations and a validated pinned regional schema. Avoid Experiments classic. Do not silently fall back to classic when an Action is unavailable.

Prioritize native App Service Kill process against exact instances or verified zone selectors, alongside native PostgreSQL forced failover. App Service process crashes are discrete effects. Replace the former Container Apps held-readiness adapter with an explicitly labeled process-crash test and at least five minutes of observation. Preserve the application-only success/latency/outage thresholds and report database recovery separately from full-phase availability.

Qualify Linux support for each selected Action and selector. If unsupported, mark the affected test BLOCKED with its documented/provider reason, describe what Windows would add if evidenced, and keep the deployment Linux. A missing application or combined test prevents an overall complete-suite PASS.

Require actual overlap before qualifying a combined fault. Zone-selected process loss has its own `HA-APP-ZONE-001` verdict. `HA-AZ-001` requires a supported correlated real-zone outage and independent affected-zone evidence across the relevant application path.

## Previous decision record and retained requirements

## D01. Application availability objective

Automatic application recovery within 180 seconds, with zero lost acknowledged writes. Use the workload, latency, success-rate, and observation-window values in [specification section 5](docs/specification.md#5-workload-procedure-and-measurements).

## D02. Three-zone architecture

The application must run on Azure App Service across three distinct observed physical availability zones. Require a plan with `zoneRedundant: true`, `maximumNumberOfZones >= 3` and actual app instance/health evidence from all three zones. D17 defines the detailed gate.

Use managed PostgreSQL zone-redundant HA with primary and standby in distinct zones. Azure manages the additional WAL replica.

## D03. Test progression

D19 sets the current progression: baseline, native instance/process crash, native zone-selected process crash, PostgreSQL failover and an explicitly qualified combined scenario. Keep HA-AZ-001 dependent on qualifying real-zone injection and evidence.

## D04. Advanced features and previews

Advanced features relevant to this non-production lab are authorized, including combined chaos scenarios and selected preview capabilities. Use Chaos Studio Workspaces and Scenarios, document their preview status, pin APIs, and execute the preview validation suite.

Authorization does not remove target allowlists, lifecycle guards, private-access requirements, or evidence checks. It does not expand testing to production or unrelated services.

## D05. Deployment target and network ownership

Use the provided subscription with Owner access. Create the complete lab from scratch, including its workload and operations VNets, private DNS, endpoints, and private runners. Use the simplified networking in D14. Delete all lab-owned resources during destruction.

Use `westeurope` as the default region, subject to mandatory regional preflight. Default VNet ranges are workload `10.81.0.0/16` and operations `10.82.0.0/16`; validate overlap before deployment and parameterize them.

Do not depend on an existing Azure network or runner pool. Subscription and tenant are deployment prerequisites; unrelated resources remain outside the lab ownership scope.

## D06. Capacity

For the App Service refactor, preserve six baseline workers and the 20-operation-per-second load. Begin with fixed capacity to keep deterministic tests comparable. Verify actual application instances across three zones and surviving capacity. D17 supersedes the earlier six-to-twelve Container Apps replicas and Dedicated D4 profile.

For PostgreSQL, start with General Purpose `Standard_D4ds_v5`, four vCores, 128 GiB storage, and zone-redundant HA. Verify regional availability and capacity before provisioning; fail preflight rather than silently weakening HA or changing the approved region.

Retain surviving-capacity validation. Use ASP.NET Core on the supported .NET LTS, Npgsql, OpenTelemetry, k6, and PowerShell for the reference implementation.

No spending cap or budget resource is required. D18 removes automatic suspension and makes the operator responsible for manual deletion.

## D07. Identity and private bootstrap

Use Owner access for initial Azure provisioning and role assignments. Use separate least-privilege managed identities for runtime, migrations, tests, chaos, and lifecycle automation. Use federated credentials for CI.

Bootstrap a lab-owned private runner automatically. Validate Microsoft Entra directory permissions separately from Azure RBAC. If tenant policy prevents automated registration creation, require tenant authorization or an administrator-created new lab-owned registration, recorded in the cleanup manifest.

## D08. Lab-owned deletion

Create Key Vault with purge protection disabled. Preserve mandatory soft delete and explicitly purge the deleted vault during teardown. Do not enable immutable storage, deletion locks, or optional retention controls that prevent lab cleanup.

Destroy deletes lab-owned resources, purgeable recoverable objects, application registrations where created and authorized, and temporary local state. Evidence export is opt-in. Mandatory Azure-managed retention follows [D12](#d12-scope-of-complete-deletion).

This is an isolated-lab exception; retain the other enterprise security controls.

## D09. Automatic suspension

Start suspension automatically 24 hours after successful build or resume. Use an Azure Automation runbook and persisted UTC deadline, independent of the operator machine and runtime VMs.

The persisted deadline is exact. Azure Automation's minute-precision start time is the first full UTC minute at or after that deadline, with a verified offset below 60 seconds. Dispatch and resource-stop latency are separate observations. A schedule must never round down before the deadline.

Execute lifecycle runbooks on a private extension-based Hybrid Runbook Worker group with two management VMs in different zones. Keep these workers and their required NAT, DNS, private endpoints, and control storage available while suspended. Cloud runbooks cannot directly reach the private control store.

Reconcile desired suspended state hourly and stop PostgreSQL again if Azure automatically starts it after seven days. Destroy removes the controller and schedules last.

Traffic, test execution, and idempotent reruns do not extend the deadline.

## D10. Lifecycle state and evidence

Keep working state in a lab-owned control store and an access-controlled local per-lab directory. The control store remains outside the runtime resources suspended by the controller and is deleted during destruction.

After successful customer-controlled cleanup, remove temporary local state. Export reports to an operator-selected destination only when explicitly requested. Do not create a separately retained Azure artifact store by default.

## D11. Random-chaos policy

Allow campaigns throughout the active UTC lab lease. Default to at most ten events and sixty minutes per campaign, with a recorded seed and five-to-fifteen-minute randomized spacing subject to fault cooldowns.

Allow one active scenario at a time; a combined scenario is an explicitly defined group of concurrent effects. Limit replica withdrawal to two of six ready replicas for five minutes and preserve the minimum twenty-minute database failover cooldown plus healthy-standby checks.

Keep scheduling disabled until deterministic and preview tests pass. Subsequent execution of configured lab-only campaigns needs no additional feature approval. Automatic suspension overrides campaign execution.

## D12. Scope of complete deletion

Accept residual information retained by Azure under mandatory service rules. Delete every lab-owned active resource, purge customer-purgeable recoverable objects, and remove temporary local lifecycle state. Create no external evidence copy by default.

Keep avoidable purge protection and immutable retention disabled. Mandatory Azure retention does not prevent successful customer-controlled cleanup, but the result must disclose those remnants and avoid claiming universal erasure.

Azure Activity Log events remain for 90 days and cannot be changed or deleted by the customer. PostgreSQL documents five-day retention of deleted-server backups.

Sources: [Azure Activity Log](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log), [Restore a deleted PostgreSQL server](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/how-to-restore-dropped-server).

## D13. Azure-allocated public IPs without BYOIP

Use Azure-allocated Standard static IPv4 addresses for the operations NAT Gateway and Bastion selected by D14. Application, database, registry, secrets, telemetry, control storage, and runner access remain private.

Exclude BYOIP and any dependency on `Microsoft.Network/AllowBringYourOwnPublicIpAddress`. Create no custom IP prefixes or public IP prefix resources; supply no literal public IP address, prefix reference, or public-IP `properties.ipTags`. Ordinary lab ownership `tags` remain required.

Remove feature-registration state from deployment prerequisites. Validate the effective policy-adjusted public-IP payload before resource deployment, regardless of feature registration state. If inherited policy adds `FirstPartyUsage` or another IP tag, stop with an explicit policy-compatibility failure. Do not register the feature, override the policy's required value, change inherited policy definitions or assignments, or silently weaken network controls. A separately authorized exemption must follow D15.

The current subscription's inherited append policy requires a public-IP tag absent from this approved configuration. D15 records the separately authorized, temporary lab-only exemption. An alternative deployment target requires separate approval and compatible effective policy.

## D14. Focused Chaos/HA laboratory networking

Deploy the networking needed to test Container Apps and PostgreSQL HA: two directly peered VNets, private endpoints, Azure-provided DNS with private-zone links to both VNets, and NSGs. Remove Azure Firewall, its policy/rules/public IP/subnet, the separate hub VNet, custom DNS proxy, and firewall-directed route tables.

Container Apps uses its managed outbound connectivity. Private operations VMs use one explicit Standard NAT Gateway on their subnet for software installation and management HTTPS access. The subnet disables default outbound access. An NSG permits required platform traffic, private HTTPS/PostgreSQL and outbound Internet HTTPS; deny other outbound traffic. The lab accepts the loss of FQDN-based egress inspection/filtering. Private service access, TLS, managed identities, and public data-plane denial remain required.

Keep Bastion in `10.82.2.0/26` within the operations VNet for SSH/source transfer into the private runner. Bastion and the NAT Gateway each reference one ordinary Azure-allocated public IP in the dedicated network group; VMs receive none. Declaring these addresses alongside DNS keeps their policy-adjusted payloads visible before dependent workload/operations modules can be evaluated. No VPN, shared hub, pre-existing runner, or network appliance is required.

A Standard NAT Gateway provides management-plane egress from one zone. Two zonal worker VMs alone do not prove zone-resilient management connectivity. Record this limitation and exclude the management NAT from claims about the application data path. Revisit management egress availability before claiming survival of a correlated real-zone outage.

Use an RG-tag policy exclusion only if the applicable live policy actually defines its key/value and condition. The inspected rule and assignment defined no RG-tag exclusion; exact governance identifiers remain in ignored local evidence. Apply no invented tag and register no BYOIP feature. D15 governs the separately approved temporary exemption. The effective public-IP contract remains a deployment gate.

## D15. Temporary lab-only public-IP policy exemption

On 4 November 2026, the operator explicitly authorized an exception for the blocking policy. Create one `Waiver` at the dedicated lab network resource-group scope, where both public IPs are declared. Set `policyDefinitionReferenceIds` to the single proven incompatible public-IP append member and add a `resourceType` selector containing only `Microsoft.Network/publicIPAddresses`. Retain `assignmentScopeValidation: Default`.

Each separately authorized waiver has a finite 24-hour lifetime; its exact live expiry remains in ignored local configuration and evidence. Preserve all other initiative members, location restrictions, policy definitions, assignments and unrelated exemptions. Do not broaden or renew the waiver automatically. Expiry ends its effect; Azure retains the exemption record until deletion.

Record the scope, reference, ownership GUID, category, expiry and GET response in the ignored ownership manifest/evidence directory. Before provisioning, verify the record and run a full-payload preview of both IPs through the unchanged D13 gate. The observed network preview contains 12 creates, no modifications/deletions and no effective public-IP tags. Full application deployment and runtime certification remain pending.

Only the network group and its exemption were created during this preparation. Continue with the same manifest; normal owned-group destruction includes its exemption. Explicit exemption enumeration supplements generic resource inventory, so an unrecorded exemption prevents cleanup.

At every later start, read the live exemption using the persistent ignored environment contract and any run-manifest records. Missing, expired or changed exemptions block Build/cycle/Resume before mutation and include explicit create-or-extend guidance; warn within two hours of expiry. A preflight failure preserves the existing lab. Keep cleanup available after expiry, retain the environment contract after destruction, and require renewed approval plus validation for any extension or replacement.

## D16. Subscription-level HA eligibility and targeted regional retry

The 4 November autonomous troubleshooting request authorizes an isolated Sweden Central retry with the same private topology and cross-zone HA requirements. The earlier North Europe attempt returned `MultiAzHaIsOfferRestricted`. Its regional capability response advertises `ZoneRedundant` for the selected SKU while the subscription-level `zoneRedundantHaSupported` is `Disabled`. Require top-level `restricted: Disabled` and `zoneRedundantHaSupported: Enabled` before infrastructure creation. Fail before resources or cleanup on an incompatible startup.

Sweden Central reports both required flags and exposes the selected SKU, zones, and PostgreSQL failover Action. The deployment defaults now select Sweden Central; D05's historical project default remains subject to these live checks. Propagate the selected location consistently through resource groups, Container Apps private DNS, storage service tags, application/controller resources, and vault purge. Region support still requires actual provisioning evidence.

Use new dedicated groups, ownership GUID, evidence and a finite D15-shaped waiver under the existing authorization to troubleshoot and retry. Preserve the previous manifest for its already-running cleanup. If that cleanup overlaps preparation, retain a full live snapshot and exclude only its exact inventoried, already-scheduled-for-deletion resource IDs from the new comparison baseline. Preserve every other current resource and perform final combined verification after both cleanups.
Use an internal Container Apps environment (`vnetConfiguration.internal: true`) while retaining zone redundancy, public network access Disabled and the environment private endpoint. Keep app ingress `external: true` so the private runner can reach the app from its peered VNet; environment type constrains that ingress to private network access. This removes the external application load-balancer endpoint from the retry. Azure can still require service-owned management/outbound public IPs, so this configuration is a tested alternative and provides no assumed exemption from governance checks. Preserve the previous manifest for its already-running cleanup. If that cleanup overlaps preparation, retain a full live snapshot and exclude only its exact inventoried, already-scheduled-for-deletion resource IDs from the new comparison baseline. Preserve every other current resource and perform final combined verification after both cleanups.

Create the exact compiled PostgreSQL resource first and verify healthy cross-zone HA before retrying the full stack. During diagnosis, retain successful owned resources and retry the failed stage in place; use the complete cycle's automatic destruction for unattended normal runs. Timestamp preview, provider provisioning and deletion phases separately from configured load-test durations. Keep service-managed infrastructure groups read-only and keep BYOIP/feature registration excluded.
