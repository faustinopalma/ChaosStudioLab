# Research and technical constraints

Recheck preview APIs, service limits, and regional availability before implementation.

The [AKS design](aks-lab.md) defines the current deployment and acceptance thresholds. The [App Service reference specification](specification.md) preserves the previous variant. This document connects current findings with the historical platform investigations.

## Current AKS findings and final App Service comparison

Updated: 7 November 2026. The active laboratory uses private AKS and PostgreSQL in Sweden Central. [The navigation hub](lab-guide.md) connects the designs, measurements and evidence limits.

- Actual private deployment qualification observed nine Ready Linux nodes, six Ready application pods on six distinct user workers, and authenticated health/checksum traffic across all three physical zones. API, application ingress, PostgreSQL, registry and vault access use their qualified private paths.
- Modern native VMSS shutdown passed exact-node and zone-selector validation. An actual exact-node Action shut down its intended one-instance user scale set for an independently observed interval exceeding 300 seconds. Authenticated shutdown caller/object claims correlated to the exact declared Chaos Workspace identity. This supplies Linux support evidence for that Action and tenant-node target; application process-deletion support has its own runtime contract.
- The first node run recovered service and acknowledged writes, but its first five-minute business success was 98.75%, below the required 99%. Kubernetes also restored six pods onto five distinct workers. Soft topology spread permits survivor-node co-location and does not automatically rebalance healthy pods onto a returned node.
- The post-measurement correction requires hostname pod anti-affinity and `externalTrafficPolicy: Local` on the private LoadBalancer Service. Azure's actual HTTP `/healthz` node-local probe was verified with a five-second interval and two failed probes. Missing node replicas remain Pending while five/four survivors serve traffic, then return to their workers. This couples external private routing to node-local availability and preserves the six-distinct-worker baseline without a post-test rollout.
- A fresh corrected baseline passed with 12,001 successful business operations, zero failures/drops, p95 11 ms and successful participation from every worker/zone. Corrected native node and remaining fault verdicts are maintained in [AKS results](aks-results.md).

**Final App Service evidence, 6 November:** Linux process deletion returned HTTP 400, `This runtime stack is not yet supported on Linux`. The explicitly authorized Windows comparison executed exact-process and verified-zone process crashes plus combined application/database Actions. Windows Npgsql cold-open stalls were resolved by disabling GSS encryption probing while retaining VerifyFull TLS and Entra authentication. Application-only HA tests passed; database/combined recovery and retention passed with separately failed full-phase availability targets. Archived reconciliation covered 92,616 acknowledged writes across 31 runs with matching checksums. See [App Service results](app-service-results.md) and [experiment limits](experiment-limits.md).

The documented Windows-only Cache Stampede with Process Crash template describes that template's eligibility. Runtime-specific process deletion and the separately qualified Linux VMSS shutdown evidence each retain their exact service, Action and target attribution.

Sources: [AKS Standard Load Balancer](https://learn.microsoft.com/en-us/azure/aks/load-balancer-standard), [Azure cloud-provider health-probe annotations](https://cloud-provider-azure.sigs.k8s.io/topics/loadbalancer/#custom-load-balancer-health-probe), and the native Action/Scenario references below. Tenant-node power faults preserve the managed regional control plane, networking and storage; full Azure-zone disaster evidence remains a separate unqualified boundary.

## Current App Service facts: three-zone and native-fault gates

The following paragraphs preserve the 5 November diagnostic snapshot. The completed 6 November comparison and current AKS findings above supersede its deployment status while retaining the original technical observations and existing section links.

**Runtime repair, 5 November 2026:** a controlled same-source Linux stack comparison restored process management and both native selector validations. The .NET10 stack ran monitor `10.0.0-rc.1.25460.1`: internal process endpoints returned HTTP200, while private SCM and ARM process listing returned HTTP409 and native validation returned internal error `-1`. Adding `WEBSITE_USE_DOTNET_MONITOR=true`, restarting the app and omitting optional ProcessName each failed to repair it. The ineffective flag was removed.

The same six business source files and dependency versions on `DOTNETCORE|9.0` run runtime9.0.22 and monitor9.0.6. ARM process listing returns HTTP200 across old and current API versions, and both exact-instance and verified-zone native validation succeeded. Private application/SCM DNS, six healthy authenticated business participants and all three physical zones remain verified. This isolates a Linux runtime-stack compatibility failure; the exact Microsoft implementation defect remains unproven. Native crash effects and recovery require their own measured executions.

**Actual Action outcome after that repair:** exact-instance, verified-zone and combined application executions fail with `ScenarioExecutionActionFailedError` and an internal service error after successful validation. Omitting optional ProcessName also fails, and an actual .NET9 execution through the already-owned Switzerland North Workspace reproduces the failure. Independent observations show no post-submission process start across the six workers. These are execution failures, distinct from the earlier .NET10 validation blocker. The provider returns run references for support and no underlying target-operation diagnosis; the complete suite remains BLOCKED.

A read-only process-contract check supplies a concrete provider investigation lead. The current [List Instance Processes contract](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/list-instance-processes?view=rest-appservice-2026-08-01) documents `ProcessInfoCollection.value[]`, with ARM-shaped process records. The actual Linux response is a bare array of `pid`, `name` and `isDefault`, including the default `dotnet` process. The [Delete Instance Process contract](https://learn.microsoft.com/en-us/rest/api/appservice/web-apps/delete-instance-process?view=rest-appservice-2026-08-01) accepts an exact instance and PID. No manual delete was attempted. The response-shape difference is verified; its causal role inside the native Action is a hypothesis requiring provider traces. Neither absent SCM traces nor the internal error establishes a private-network or blanket Linux restriction.

Fresh .NET9 BASE-001 passed with p95 124 ms and 100% business/canary success. A second native PostgreSQL run recovered in 32.288 s with complete recovery/stability windows and full write retention; full-phase availability separately failed at 97.620481%. Two harness audit assumptions were repaired from real evidence: Activity Log ingestion can lag completion, and one correlated provider completion was recorded 35.627 s after native end. The [identity contract](implementation-contracts.md#native-action-contracts) now binds an in-run authenticated start to its exact correlated completion within a bounded lifecycle tail, independently of the recovery clock. Original failures and explicit reconciliations remain preserved.

**Bounded runtime support:** the live catalog marks .NET9 `Near`, with `end_of_life=2026-11-10`. The application project and App Service `siteConfig.linuxFxVersion` now select this qualified runtime for the current laboratory. Preflight and every measurement reject an expired, unqualified or ambiguous runtime; actual app configuration must match. Requalify a supported native-compatible stack before that date. The original checksummed .NET10 package/configuration remain available privately for operational rollback.

The comparison's CLI startup tracker reported six failed starts after ten minutes. Independently, SCM deployment status4/complete, the active ZIP checksum, actual main-container runtime and successful private all-instance business/health probes prove publication. This tracking failure remains recorded. New publication waits for SCM completion with `--async false --track-status false`; PC orchestration then requires private authentication, durability and all-instance placement/participation before declaring readiness.

Regional qualification also exposed residual Bicep location allowlists. Active templates and script selection now consistently accept qualified regional names while preserving live quota, service, exact ownership, policy and observed three-zone gates. Four additional actual six-worker P1v3 AZ allocation validations in US hosting regions returned zero subscription quota; no hosting move or resource creation resulted.

Verified against official documentation on 4 November 2026. These findings govern the App Service refactor; the numbered sections below retain the previous Container Apps investigation.

- App Service plan zone redundancy is configured on `Microsoft.Web/serverfarms`. Its `maximumNumberOfZones` is a plan/scale-unit capability. A zone-enabled region and `zoneRedundant: true` do not establish three-zone capability for the actual plan.
- The lab requires at least three supported zones and six baseline application instances across three observed physical zones. App Service's documented platform minimum of two instances is below this laboratory's requirement.
- The Web App instance-list REST API, documented with version `2024-04-01`, exposes `physicalZone`. The portal displays this inventory under Web App > Health check > Instances. Preserve raw responses, correlate instance IDs with health and traffic, and refresh before faults and after recovery.
- Placement is point-in-time evidence. Per-app scaling can allow an app to use fewer workers than its plan. Disable it for this lab and verify the actual application's participating instances.
- Outbound regional VNet Integration and inbound Private Endpoint are complementary paths. Use a dedicated `Microsoft.Web/serverFarms` integration subnet, separate private-endpoint subnet and private DNS records for both application and SCM/Kudu.
- Workspaces documents native App Service Kill process and Restart. Kill process exposes `InstanceIds` and `Zones` and is a discrete Action. The process-crash Scenario template is documented for Windows App Service only; qualify Linux eligibility for the actual regional Action/runtime/selector combination separately.
- A zone-selected process crash and a correlated infrastructure-zone outage require separate verdicts. Do not transfer a component or earlier Container Apps PASS to the new App Service acceptance gates.

Sources: [Configure zone redundancy and inspect physical zones](https://learn.microsoft.com/en-us/azure/app-service/configure-zone-redundancy), [App Service reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service), [VNet Integration](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration), [Private Endpoint](https://learn.microsoft.com/en-us/azure/app-service/overview-private-endpoint), [Workspaces Actions](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources), [Scenario template limitations](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios).

### Linux baseline and Windows test coverage

The operator selected **Linux** on 4 November 2026. Preserve three-zone application placement, private ingress, VNet Integration and PostgreSQL HA. The ASP.NET Core application has no identified Windows-specific dependency.

This table separates documented platform/template support from actual test qualification. Both Linux and an explicit Windows comparison variant have been executed against the same private architecture.

| Capability/test | Linux evidence and remaining gate | Windows evidence and possible advantage |
| --- | --- | --- |
| .NET app, zone redundancy and private paths | Qualified Linux `DOTNETCORE|9.0`, private SCM publication and all-six-worker health/business participation in three physical zones verified; bounded support through 10 November 2026 | Same required placement/private-path checks; no measured HA advantage established |
| Native App Service Restart | Listed for `Microsoft.Web/sites`; exact Linux/runtime behavior remains unqualified | Listed for the same resource type; catalog entry alone supplies no comparative result |
| Native Kill process on an instance | Live regional schema describes Linux `dotnet/node` workers and exposes `InstanceIds`. .NET 9 validation passes, but actual Actions fail internally. Direct process deletion returns HTTP 400 `This runtime stack is not yet supported on Linux` on .NET 8, .NET 9 and Node.js 22; .NET 10/11 listing returns 409 (dotnet-monitor); Python 3.13, Java 21 and container listing return 400; Node.js 24 lists no processes. **BLOCKED** | Direct deletion returns 204. Explicit `processName` is rejected in validation, so the Scenario omits it; the default target is the dotnet worker under out-of-process hosting. HA-APP-001 **PASS** on 6 November: exact replacement 12.7 s after acceptance, zero failed operations |
| Native Kill process by zone | Live schema exposes string-array `Zones`; actual subscription mapping `1 -> spaincentral-az1`, `2 -> spaincentral-az2`, `3 -> spaincentral-az3` verified. Execution fails for the same platform reason. **BLOCKED** | HA-APP-ZONE-001 **PASS**: both workers in the selected physical zone replaced 11–13 s after acceptance, zero failed operations |
| Cache Stampede with Process Crash template | Official Scenario documentation explicitly excludes Linux App Service | Explicitly documented Windows support: a concrete template-coverage advantage |
| Custom App Service/PostgreSQL combined test | Blocked by the application Action | HA-COMBINED-001 **PASS**: process replacement bracketed by independently observed database failures, 34.989 s recovery, zero acknowledged write loss; full-phase availability 97.324% reported separately |
| Sustained real-zone loss, HA-AZ-001 | Requires supported correlated infrastructure-zone injection and independent evidence | Same: the OS choice supplies no real-zone evidence. **BLOCKED** guard on both |

**Current conclusion:** for this lab, Windows App Service has a measured coverage advantage. Native process crash, by instance and by zone, runs and recovers on Windows, while every tested Linux stack fails App Service process deletion. [D23](../DECISIONS-ACCEPTED.md#d23-explicit-windows-comparison-variant-for-native-process-crash) records the explicit Windows comparison variant; the Linux deployment and its BLOCKED verdicts are retained. The [execution results](app-service-results.md#windows-comparison-variant-complete-native-suite-6-november) contain the Windows measurements. On Windows, set `GssEncryptionMode.Disable` for Npgsql to avoid multi-second Kerberos/SSPI probing on each physical connection.

Before attempting each Linux Action, inspect its current regional schema, OS/runtime prerequisites and selector semantics. Save exact documentation or provider eligibility errors. Use a short, bounded qualification on the owned app when execution evidence is required. Distinguish an unavailable Action from invalid parameters, missing permissions or a failed private path.

If a Linux test is unsupported, mark it BLOCKED and explain the precise lost coverage and any evidenced Windows equivalent. If evidence is insufficient, report the eligibility as unqualified rather than asserting incompatibility. A complete suite requires qualifying application/combined evidence. [D22](../DECISIONS-ACCEPTED.md#d22-autonomous-completion-and-withdrawn-operational-prohibitions) records the current autonomous operating authorization; Linux/native remains the implementation being qualified.

### Fresh foreground catalog qualification

**Earlier .NET10 execution, 5 November:** private PostgreSQL Ready/Healthy zone-redundant HA and the sole private runner were restored. Direct application configuration exposed `alwaysOn=false`; an in-place premeasurement repair restored actual `alwaysOn=true` and six participating workers in three physical zones. The cause of that drift remains unknown. That baseline passed with 100% business success, zero errors/drops and p95 122 ms. The [execution report](app-service-results.md) separates historical and latest package-specific results.

The earlier .NET10 Linux `/instances/{instanceId}/processes` endpoint returned `Conflict(The dotnet-monitor tool is not configured to run)`, including after successful publication. Independently completed read-only container inspection through the private runner found the `DiagServer`, `dotnet-monitor` and application `dotnet` processes. The documented `WEBSITE_DISABLE_DOTNET_MONITOR` app setting is absent. The [verified Microsoft Q&A](https://learn.microsoft.com/en-us/answers/questions/1282283/azure-app-service-on-linux-dotnet-monitor-process) discusses disabling the monitor; it supplies no verified remedy for this management-API conflict. The actual runtime catalog lists `DOTNETCORE|10.0` as Active through November 2028. Subsequent controlled repairs and the validation-qualified bounded .NET9 comparison are recorded above; private access remained enforced.

The actual exact-instance native execution was accepted at 08:04:15 UTC and ended Failed at 08:04:26 UTC with `ScenarioExecutionTargetValidationError`. Its resource error is internal service error `-1`; no successful Action summary or process-replacement evidence exists. Repeated non-fault validation returned `RequiresAttention`, including after fresh discovery. Source-compiled, ARM-validated, exactly previewed regional Workspaces reused the same UAMI/unchanged targets. Both selectors reproduce the failure through all eight advertised locations: Sweden Central, Switzerland North, East US 2, West US 2, North Europe, UK South, Japan East and West Central US. Discovery passed in every additional location. These are eight Workspace-region observations against the same Spain Central application. They establish the current configuration's blocker without establishing a blanket Linux restriction or a comparison of application hosting regions.

The Sweden Central Workspace successfully executed native PostgreSQL failover. Independent observation proves a primary/standby swap from zones 1/2 to 2/1 and 34.601 s recovery, followed by a complete five-minute stable window. All 5,354 current writes and the complete 16,486-write measurement history plus 12 smoke writes were retained/checksummed. Full-phase availability separately failed at 97.481598%; the [execution report](app-service-results.md) preserves errors, drops and both verdicts.

Existing exact-app Website Contributor, exact-server Contributor and workload discovery Reader assignments are source-defined and verified. Execution principal metadata differs from the Workspace UAMI; its meaning remains unresolved. The original database harness failure was preserved, and current tested completion code reconciled the existing execution using its exact compiled Action/parameters/target/success summary plus the authoritative correlated PostgreSQL Activity Log caller and authenticated object claim, both matching the declared UAMI. The terminal event's optional HTTP metadata is absent; the ordered request start supplies a nonempty client-request ID. Ambiguous, missing, wrong-identity or uncorrelated evidence remains rejected. Application identity handling is unchanged. No speculative role grant was made. Raw provider references and audit proof remain ignored/private.

The first Scenario PUT rejected an empty `ProcessName` with `Properties.Actions[0].Parameters[0].Value: The Value field is required`, although ARM validation accepted it. The corrected definition explicitly supplies `dotnet`, matching the configured Linux startup command. Repeated compilation, ARM validation and four-resource literal-owned preview passed, and both Scenarios/configurations were deployed successfully. This confirms definition acceptance independently of runtime fault support.

A read-only qualification on 4 November 2026 confirmed the following provider contracts. Actual context and responses belong in ignored run evidence.

Regional selection now follows D21 and the operator's expanded search authorization. Italy North reports PostgreSQL `restricted: Disabled` and `zoneRedundantHaSupported: Enabled`; its modern Action endpoint returns `NoRegisteredProviderFound` and Workspace deployment availability omits Italy North. These facts apply to Workspace placement. Microsoft explicitly documents that a [Workspace can target resources in any Azure region](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-region-availability#regional-availability-of-chaos-studio-workspaces), independently of its deployment region. The previous co-location assumption was overly restrictive. Italy North's separate six-worker Linux P1v3 allocation validation still reports AZ quota zero.

The earlier Sweden Central scope deployment created the dedicated groups and configured single-reference, public-IP-only exemption, with finite 24-hour expiry. Its actual six-worker Linux P1v3 plan create was rejected: `P1v3 AZ VMs` limit 0, usage 0, required 6. P1v4, P1v2 and P2v3 ARM validations also returned `InternalSubscriptionIsOverQuotaForSku`, with zero corresponding AZ-worker quota. Region/SKU availability and the generic regional quota of ten (`isQuotaApplicable=false`) do not establish allocation eligibility. The subsequent Spain Central deployment supersedes this allocation blocker.

The source default remains P1v3. Expanded source-derived ARM allocation validation found **Spain Central / P1v3** succeeds for the unchanged Linux/reserved/zone-redundant/capacity-six resource. Its PostgreSQL subscription-level HA flags are enabled and unrestricted. The actual Spain Central plan has six Linux workers, zone redundancy and `maximumNumberOfZones: 3`; subsequent private health/business sampling verified all six workers in three physical zones. Retain the database/workload VNet there. Every Spain Central VM SKU is restricted for this subscription, so the single runner and operations VNet/NAT/Bastion/public IPs and Workspace use Sweden Central with global peering. Current groups, ownership and group metadata location are preserved. Native runtime/effect verdicts remain unqualified.

Additional same-region-Workspace candidates Switzerland North, UK South and Japan East rejected all six tested Premium SKUs with AZ allocation quota zero. France Central, Germany West Central, Norway East and Poland Central likewise rejected the six tested SKUs before Spain Central passed on P1v3. Other screened regions failed subscription-level PostgreSQL HA eligibility. The exact named Switzerland North `P1v3_AZ` CLI quota reports applicable limit ten and usage zero, while ARM allocation reports zero; neither advertisement nor quota discovery substitutes for provider validation. No quota update, inherited-policy change, OS/zone/worker downgrade or cleanup was performed.

- `GET /subscriptions/{subscriptionId}/providers/Microsoft.Chaos/locations/{location}/actions?api-version=2026-08-01-preview` returns the canonical process-crash ID `urn:csci:microsoft:appservice:killprocess/1.0.0`, type `Discrete`, target `Microsoft.Web/sites`.
- `ProcessName.description` says: "Leave empty to kill the main worker process (w3wp for Windows, dotnet/node for Linux)." This supplies explicit Linux catalog evidence. Successful execution against the actual Linux runtime/private configuration remains a separate gate.
- `InstanceIds` and `Zones` accept arrays of strings or null. Their descriptions allow all selected instances and all instances in selected zones. An empty selection can choose a random instance; deterministic tests must supply an exact nonempty selection. The schema does not establish how physical-zone labels map to zone-selector strings.
- Required process permissions are `Microsoft.Web/sites/read`, `Microsoft.Web/sites/instances/read`, `Microsoft.Web/sites/instances/processes/read` and `Microsoft.Web/sites/instances/processes/delete`.
- PostgreSQL retains canonical ID `urn:csci:microsoft:azurepostgresql:failover/1.0.0`. The regional schema defines `ForcedFailover` as enum value `1`; `RestoreOnStop` and `SkipIneligibleServers` are booleans. Scenario parameter serialization still requires source-derived ARM validation.
- `az webapp list-runtimes --os linux` returns object entries in the current CLI. The .NET 10 entry has `config = DOTNETCORE|10.0`, `os = Linux`, `support = Active`. A JMESPath expression assuming string-only entries fails and must not be used as evidence of runtime unavailability.
- App Service [Private Endpoint documentation](https://learn.microsoft.com/en-us/azure/app-service/overview-private-endpoint) supports Linux and Windows and requires separate integration/endpoint subnets. A private DNS zone group creates both application and SCM records under `privatelink.azurewebsites.net`. Private package publication, authentication and public-denial probes still require the actual deployment.

The repeatable [foreground preflight](../scripts/Test-AppServicePreflight.ps1) creates a fresh ignored manifest, captures raw catalog/runtime/HA/baseline evidence, checks exact old-group absence and reuses the existing policy-exemption guard. Each CLI child process has a hard deadline; stage output identifies buffering. It performs no Azure writes or fault execution and records all six test verdicts separately.

An absent/expired required exemption blocks provisioning until its exact narrow contract is restored under current D22 authorization and revalidated. Retain the configured assignment, single policy reference, public-IP resource selector and finite expiry. Actual plan capability, three-zone participation and private SCM are now verified; native application/combined effects remain blocked separately.

## Historical Container Apps investigation

The following service-specific placement, adapter and lifecycle discussion belongs to the previous design. The current specification supersedes conflicting recommendations.

## 1. Container Apps and availability zones

Zone redundancy is configured on the Container Apps environment at creation. Azure distributes the underlying infrastructure and schedules app replicas across availability zones. Customers control replica counts, compute profiles, and scaling; Azure controls individual replica placement.

Microsoft recommends at least two minimum replicas for multi-zone distribution. A larger minimum can preserve capacity during detection and replacement. The lab proposes six replicas, then measures whether the surviving capacity can sustain the workload.

During a zone failure, ingress redirects traffic to healthy replicas and new replicas can be scheduled in healthy zones. Existing replicas can remain in their current zones after recovery; rebalancing happens gradually.

The documentation recommends application-layer disruption tests, including deliberately failing health endpoints. These tests validate traffic withdrawal and remaining capacity. A replica identifier or a reduced replica count alone supplies no verified zone identity.

Sources: [Container Apps reliability](https://learn.microsoft.com/en-us/azure/reliability/reliability-container-apps), [Create a zone-redundant container app](https://learn.microsoft.com/en-us/azure/container-apps/how-to-zone-redundancy).

## 2. PostgreSQL HA topology and recovery

Zone-redundant PostgreSQL HA uses a primary and standby in different availability zones. The service synchronously preserves committed data and automatically promotes the standby when required.

Current documentation also describes a WAL replica in a separate zone for commit quorum. The WAL replica supports durability; promotion is limited to the standby. The customer-facing placement controls remain primary and standby zone selection. This distinction matters when specifying an explicitly controlled three-zone database topology.

Burstable compute does not support zone-redundant HA. Select a supported tier and verify actual primary/standby placement after deployment. Reject a same-zone fallback for this lab.

Microsoft documents typical zone-failure recovery of 60-120 seconds. Client reconnection, DNS behavior, token handling, retries, and connection-pool recovery affect application recovery. Measure that recovery at the business API.

A stable server hostname survives failover. Existing database connections can break. A forced failover immediately takes the primary down and tests unplanned-failure behavior; a planned failover prepares the standby first.

Wait at least 15-20 minutes between failovers so that the new standby can be established. The specification uses a minimum 20-minute guard plus an explicit healthy-standby check.

Zero lost acknowledged writes is the data-integrity target. A timeout can leave the client uncertain whether its write committed. Idempotent operation IDs and reconciliation resolve that uncertainty.

Sources: [PostgreSQL HA concepts](https://learn.microsoft.com/en-us/azure/postgresql/high-availability/concepts-high-availability), [Configure HA and initiate failover](https://learn.microsoft.com/en-us/azure/postgresql/high-availability/how-to-configure-high-availability).

## 3. Current Chaos Studio model

Microsoft currently recommends Chaos Studio Workspaces for new resilience tests. Workspaces discover resources in a defined scope and execute Scenarios composed of Actions. Workspaces and Scenarios are in public preview.

Custom Scenarios can be expressed in Bicep as `Microsoft.Chaos/workspaces/scenarios`. The current supported-resource catalog includes PostgreSQL Flexible Server failover and Azure Automation runbooks.

The PostgreSQL action supports `PlannedFailover` and `ForcedFailover`. Its optional `RestoreOnStop` setting can initiate a planned return to the original primary. The lab disables automatic restoration to avoid an unobserved second failover and premature back-to-back operations.

The older Experiments (classic) fault library has a separate resource model. Its entries do not establish Action availability in Workspaces. During implementation, discover the regional Action catalog and validate the selected Bicep API and parameters.

Sources: [Workspaces overview](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview), [Supported resources and Actions](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources), [Scenario catalog and Bicep authoring](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios).

## 4. What a zone-down Scenario can establish

The current **Compute Zone Down + PostgreSQL Failover** template combines VM/VMSS shutdown actions with PostgreSQL failover. Its compute actions target customer-visible virtual machines and scale sets.

The current Workspaces catalog has no direct `Microsoft.App/containerApps` or `Microsoft.App/managedEnvironments` fault action. Container Apps' underlying managed compute must remain outside any assumed VMSS shutdown scope.

A PostgreSQL failover Scenario can establish that the database role changed and the application recovered. A replica-withdrawal adapter can establish that ingress and surviving application capacity behaved correctly. Running them together provides evidence for correlated failure effects.

The complete zone-outage claim requires evidence that a specific real availability zone was affected across the relevant application dependencies. Require this evidence before claiming full-zone validation.

The PostgreSQL tutorial also warns about resource-group discovery: non-HA servers and read replicas can cause failover actions to fail. The lab must use an exact target inventory, resource filters, and fail-closed eligibility checks.

Sources: [Scenario templates](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios), [PostgreSQL zone-down tutorial](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-tutorial-postgresql-failover), [Supported Actions](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources).

## 5. Private ingress and VNet integration

Container Apps supports environment private endpoints in workload profiles environments for both Consumption and Dedicated profiles. The environment can also integrate with a customer VNet.

These features provide two connectivity paths:

- The environment private endpoint provides private inbound client access.
- The environment infrastructure subnet provides VNet-integrated outbound access to private dependencies and controlled egress.

Disable public network access on the environment when using the private endpoint. Configure its private DNS zone as `privatelink.<region>.azurecontainerapps.io`.

Microsoft's Private Link example uses app-level external ingress. Here, external ingress means clients outside the Container Apps environment can reach the app through the environment ingress path. Environment-level network restrictions determine whether Internet access is permitted.

Sources: [Container Apps private endpoints and DNS](https://learn.microsoft.com/en-us/azure/container-apps/private-endpoints-with-dns), [Private endpoint deployment example](https://learn.microsoft.com/en-us/azure/container-apps/how-to-use-private-endpoint).

## 6. PostgreSQL networking choice

PostgreSQL Flexible Server supports delegated-subnet VNet integration and Private Link-compatible networking as distinct deployment choices.

The current Private Link documentation requires the server's networking model to use public-access mode rather than delegated-subnet integration. Public network access can then be disabled, leaving connectivity through approved private endpoints.

For this lab, choose that Private Link-compatible model, disable public access, and resolve the server FQDN through private DNS. PostgreSQL HA and Microsoft Entra authentication are supported with Private Link.

Creating a private endpoint does not itself close a service's public access. Verify the service-level setting and perform an Internet negative-connectivity check.

Sources: [PostgreSQL Private Link](https://learn.microsoft.com/en-us/azure/postgresql/network/concepts-networking-private-link), [Enable or disable PostgreSQL public access](https://learn.microsoft.com/en-us/azure/postgresql/network/how-to-networking-servers-deployed-public-access-enable-disable-public-access).

## 7. Focused lab egress, DNS, and operations

Container Apps workload profiles environments support custom egress through UDRs or NAT. D14 uses managed outbound connectivity and direct private routing, with no custom UDR or Azure Firewall. Operations VMs use a subnet NAT Gateway for explicit Internet egress.

Preserve required platform, identity, registry, package-source and monitoring connectivity. DNS resolution for required Container Apps and underlying platform dependencies must remain available. Arbitrary Internet denial without these dependencies can prevent startup, scaling, image pulls, or identity operations. The simplified lab accepts HTTPS egress without FQDN inspection; operations NSGs deny other unneeded outbound traffic.

Private runners need working routes, DNS, and authorization for the application, database, registry, and evidence store. A public CI runner cannot access those private data planes solely because it can deploy resources through Azure Resource Manager.

ACR private connectivity requires Premium. Plan DNS records for both registry and data endpoints. Verify image pulls from a newly created replica, so that a cached image cannot hide a networking problem.

Azure-provided DNS and private-zone links remove the need for a DNS VM or appliance. The Standard operations NAT Gateway remains a single-zone management egress dependency outside the application request path; two zonal worker VMs alone do not prove management connectivity through zone loss.

Sources: [Container Apps networking](https://learn.microsoft.com/en-us/azure/container-apps/networking), [NAT Gateway overview and Standard zonal scope](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview), [ACR private endpoints](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-private-endpoints).

### 7.1 Azure-allocated public IPs and the observed inherited policy

Standard static public IPv4 addresses can be allocated from Azure's address pool. BYOIP uses an externally owned address range provisioned as a custom IP prefix. [D13](../DECISIONS-ACCEPTED.md#d13-azure-allocated-public-ips-without-byoip) selects Azure allocation and excludes BYOIP-related inputs and public-IP `ipTags`.

Read-only inspection on 4 November 2026 identified an inherited policy in the current tenant:

- Management-group scope, assignment, initiative reference and definition: exact identifiers retained only in ignored local policy evidence.
- Condition: resource type is `Microsoft.Network/publicIPAddresses` and the count of IP tags matching `FirstPartyUsage=/Unprivileged` is less than one.
- Effect: `append` adds that exact entry to `Microsoft.Network/publicIPAddresses/ipTags[*]`.

The first attempt's saved effective what-if contains that appended tag on both public IPs. The Bicep source supplied no such tag or prefix. Both actual writes failed with `SubscriptionNotRegisteredForFeature` naming `AllowBringYourOwnPublicIpAddress`. This establishes a policy-induced payload difference associated with the failure; the Network provider's internal feature-check implementation has not been independently observed.

Changing the public-IP API version did not resolve the failure. An empty `ipTags` array also satisfies the append condition. Treat this as a governance-compatibility gate and inspect the effective payload; feature registration is excluded by the current design.

Sources: [Azure public IP addresses](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/public-ip-addresses), [Custom IP address prefix (BYOIP)](https://learn.microsoft.com/en-us/azure/virtual-network/ip-services/custom-ip-address-prefix), read-only ARM GET of the exact management-group policy definition, and the saved first-cycle what-if described in the [execution report](first-cycle-results.md).

## 8. Identity and private observability

Use application managed identity for PostgreSQL authentication and an identity-aware Npgsql token provider. Token renewal must continue after connection failures and pool replacement. Bootstrap database principals and grants with a separate privileged migration path.

Azure Monitor uses an Azure Monitor Private Link Scope to group supported monitoring resources behind private endpoints. Shared monitoring endpoints affect DNS behavior across resources, so coordinate the scope and DNS configuration with the enterprise platform team.

Application telemetry and service-managed diagnostic delivery follow different paths. Validate both under the final access restrictions before injecting faults. Export raw client measurements independently so that a telemetry outage cannot produce a false pass.

Sources: [PostgreSQL authentication library for .NET](https://learn.microsoft.com/en-us/dotnet/api/overview/azure/microsoft.azure.postgresql.auth-readme?view=azure-dotnet), [Azure Monitor Private Link](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-security), [Container Apps log options](https://learn.microsoft.com/en-us/azure/container-apps/log-options).

## 9. Controlled replica faults

The documented Container Apps replica CLI provides listing and inspection. The console/exec interface can select a revision, replica, and container.

A lab-specific local fault helper is a candidate adapter for that interface. Its automated execution, permissions, TTL, and cleanup require a prototype. It must not depend on PostgreSQL remaining available during the combined test.

Failing readiness exercises traffic withdrawal and capacity loss. A process crash additionally exercises restart behavior. Track these as separate fault types and preserve their boundaries in reports.

Sources: [Container Apps replica commands](https://learn.microsoft.com/en-us/cli/azure/containerapp/replica?view=azure-cli-latest), [Container console and replica selection](https://learn.microsoft.com/en-us/azure/container-apps/container-console).

## 10. Reliable conclusions from chaos tests

Chaos action success confirms execution of an action. Application success requires independent assertions about requests, writes, recovery, and cleanup.

Measure raw HTTP attempts, eventual completion of idempotent writes, and acknowledged-write durability separately. Report failures and timeouts alongside successful-request latency. Preserve inconclusive results when evidence is missing.

Use seeded random selection only after deterministic tests establish the expected behavior. Bound the blast radius, execution window, fault duration, and campaign size. Persist the realized plan because a seed alone cannot reproduce changed resource discovery.

HA covers infrastructure failure. Accidental data deletion, invalid migrations, and logical corruption require backup and restore procedures. Keep those procedures outside the first zone-resilience experiment.

## 11. Shutdown and restart

### PostgreSQL

PostgreSQL Flexible Server provides server stop and start operations. Azure automatically starts a stopped server after seven days. Scheduled maintenance can also briefly start a stopped server before returning it to the stopped state.

Stopping compute preserves the server and its data. Validate the exact HA configuration and wait for observed state transitions; a request accepted by Azure does not prove that the server is stopped.

The lifecycle controller reconciles desired suspended state hourly. If Azure starts PostgreSQL while the lab is suspended, the controller stops it again after checking that no authorized resume or conflicting management operation is in progress.

Source: [Stop PostgreSQL compute](https://learn.microsoft.com/en-us/azure/postgresql/configure-maintain/how-to-stop-server).

### Container Apps

Deactivating a revision stops its running replicas. Preserve the active revision list and traffic configuration before deactivation so that resume restores the intended version.

Verify actual Dedicated node allocation after reducing minimum capacity. Deactivating app replicas alone does not establish that profile nodes were released.

Preserve the environment, image, private connectivity, and prior scaling configuration so that resume restores the HA baseline.

Sources: [Revision deactivation](https://learn.microsoft.com/en-us/azure/container-apps/revisions-manage#revision-deactivate), [Workload profile scaling](https://learn.microsoft.com/en-us/azure/container-apps/workload-profiles-manage-cli).

### Network and supporting services

The simplified lab retains its Standard NAT Gateway, Bastion, direct peering, Azure DNS/private-zone links and private endpoints while runtime compute is suspended. NAT provides outbound connectivity for private management VMs and permits no unsolicited Internet inbound connections.

Runtime VM compute must reach a deallocated state. Preserve the management workers, required networking, private endpoints, state storage, and monitoring. Inventory every retained resource and its operational reason.

Source: [NAT Gateway overview](https://learn.microsoft.com/en-us/azure/nat-gateway/nat-overview).

## 12. Full teardown and mandatory Azure retention

Deleting the lab resource groups is the primary teardown operation. Verify lab-owned objects created at subscription, tenant, shared-network, or service-managed scope as well.

For this disposable lab, omit `enablePurgeProtection` when creating Key Vault, then verify protection remains unenabled. The API rejects an explicit `false` value even on initial creation; the 4 November live attempt reproduced this and verified creation after omission. Mandatory soft delete remains enabled. Purge the vault after deletion with the appropriate authorization and verify that no recoverable vault remains.

Purge protection, once enabled, cannot be disabled or bypassed. Fail preflight if policy forces an incompatible configuration. Do not silently deploy a vault that prevents the required lab cleanup.

Some retention is service-managed. Azure Activity Log entries cannot be changed or deleted and remain for 90 days. PostgreSQL documents retention of a deleted server's backup for five days. Disabling vault purge protection does not change those rules.

Delete customer-controlled resources and purgeable objects, remove temporary local data, and export evidence only on explicit request. Report mandatory Azure-managed remnants without claiming universal erasure.

Sources: [Key Vault soft delete and purge protection](https://learn.microsoft.com/en-us/azure/key-vault/general/key-vault-recovery#what-are-soft-delete-and-purge-protection), [Azure Activity Log](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log), [Restore a deleted PostgreSQL server](https://learn.microsoft.com/en-us/azure/postgresql/backup-restore/how-to-restore-dropped-server).

## 13. Owner access and directory permissions

Subscription Owner can manage Azure resources and assign Azure RBAC roles. Microsoft Entra directory roles use a separate authorization system.

Check registration creation and deletion permissions before provisioning the lab. If tenant policy denies creation, obtain tenant authorization or have an administrator create a new lab-owned registration and establish its cleanup permissions. Subscription Owner alone cannot establish that this directory step will succeed.

Source: [Azure roles and Microsoft Entra roles](https://learn.microsoft.com/en-us/azure/role-based-access-control/rbac-and-directory-admin-roles).

## 14. Independent automatic suspension

Azure Automation supports one-time and recurring schedules. Arm a one-time run for 24 hours after successful build or resume, and maintain an hourly reconciliation schedule while the lab is suspended.

Automation cloud jobs cannot directly access services secured by private endpoints. Execute lifecycle runbooks on an extension-based Hybrid Runbook Worker group in the private management network. Use two workers in different zones and preserve their required identity, DNS, NAT, Automation private endpoint, and control-store connectivity.

Keep this management group outside the runtime suspension and chaos scope. Include it in destruction, after runtime cleanup and verification. Validate schedule timing, worker failover, operator disconnection, and recovery from missed runs.

Sources: [Automation schedules](https://learn.microsoft.com/en-us/azure/automation/shared-resources/schedules), [Automation Private Link limitations](https://learn.microsoft.com/en-us/azure/automation/how-to/private-link-security#limitations), [Extension-based Hybrid Runbook Workers](https://learn.microsoft.com/en-us/azure/automation/extension-based-hybrid-runbook-worker-install).

## 15. Preview test evidence

The lab authorizes relevant advanced and preview capabilities. Maintain an explicit feature inventory and document the preview classification and pinned version of each selected feature.

Execute schema, deployment, actual Scenario execution, cancellation, scope-isolation, telemetry, and cleanup tests. Record results with API versions and resource IDs. Approval to use a preview feature must not be reported as a successful test.

Source: [Chaos Studio Workspaces](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-overview).
