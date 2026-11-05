# Implementation specification

Updated: 5 November 2026.

**Current target: private Linux Azure App Service deployed across three observed availability zones, with private PostgreSQL HA and PC-driven execution.** The private architecture, six-worker/three-zone participation and complete BASE-001 are verified. Required native application/combined coverage remains blocked by actual provider target-validation failures; database-effect qualification is in progress. Actual results are recorded separately.

[D22](../DECISIONS-ACCEPTED.md#d22-autonomous-completion-and-withdrawn-operational-prohibitions) records the operator's withdrawal of previous project-level operational prohibitions and autonomous completion without a cost ceiling. Existing database start, necessary lab repairs, exemption maintenance, regional alternatives and the complete requested suite are authorized.

Apply [D17-D19](../DECISIONS-ACCEPTED.md#d17-private-azure-app-service-across-three-zones) over the superseded Container Apps and automatic-lifecycle decisions. The previous specification, implementation and diagrams are recoverable from Git tag `baseline-before-app-service-refactor`.

[D21](../DECISIONS-ACCEPTED.md#d21-expanded-regional-qualification-and-cross-region-workspaces) authorizes expanded regional qualification after the original Italy North/Sweden Central preferences. The selected workload is **Spain Central / P1v3**, with PostgreSQL and the workload VNet in the same region. The single private runner, operations VNet/NAT/Bastion and modern **Chaos Workspace remain in Sweden Central**, connected through global VNet peering. Workspaces support cross-region native targeting. Retain the same approved private CLI profile/environment, ownership manifest and exact three group IDs; their group metadata remains Sweden Central. Actual plan capability, placement/private access and native effects remain mandatory live gates.

## 1. Objective and requirements

Use the native Chaos Studio experience to measure application availability, surviving capacity, recovery and acknowledged-write durability during application and database faults.

| ID | Requirement |
| --- | --- |
| R1 | Host the operator-selected Linux baseline on Azure App Service, using a Web App and an App Service Plan. Qualify native Action/runtime support and document any evidenced Windows coverage advantage. |
| R2 | Retain Azure Database for PostgreSQL Flexible Server with managed zone-redundant HA and distinct primary/standby zones. |
| R3 | Run the application across **three distinct observed physical availability zones** in one region. Verify the actual application's instance placement and health. A regional zone count, a plan capability or a configured worker count alone cannot close this requirement. |
| R4 | Provide both App Service VNet Integration for outbound private dependency access and an App Service Private Endpoint for inbound private HTTPS. Disable public data-plane access to the application and database. |
| R5 | Use Chaos Studio **Workspaces, Scenarios and Actions**. Avoid Experiments classic. Verify the regional Action catalog and preview contract before provisioning dependent resources. |
| R6 | Run deployment orchestration from the operator's PC, with visible step progress, bounded waits and local logs. Use the private runner for operations requiring private network access. |
| R7 | Execute the complete requested suite under the current operator authorization, report each verdict and leave the final environment available for subsequent operator teardown. |
| R8 | Remove the Automation Account, Hybrid Workers, two lifecycle-worker VMs, lifecycle control store, automatic suspension, Suspend/Resume workflow and random-chaos scheduler from the active architecture. |
| R9 | Retain authenticated access, managed identities, TLS validation, private DNS, NSGs, exact ownership boundaries and independently collected raw measurements. |
| R10 | Provide the required private management path through operations NAT/Bastion. Qualify effective network payloads and policy responses against the deployed topology. |
| R11 | Preserve unrelated subscription resources. Keep real environment identifiers, authentication state and raw evidence in ignored local paths. |

Three application zones and PostgreSQL HA are separate placement contracts. PostgreSQL retains its service-managed primary/standby topology; record the service-managed WAL role separately where observable.

## 2. Target architecture

### Application and capacity

Use one dedicated Linux App Service Plan and one stateless Web App. Select a Premium SKU and regional scale unit that support the required features.

| Resource/property | Required configuration or evidence |
| --- | --- |
| App Service Plan, `Microsoft.Web/serverfarms` | Linux plan (`kind = linux`, `properties.reserved = true`), `properties.zoneRedundant = true`, `properties.perSiteScaling = false` for this single-app lab |
| Plan capacity, `sku.capacity` | Preserve the earlier six-worker baseline, now expressed as App Service workers; at least three must remain configured in every normal-operation scaling profile |
| Plan capability, `properties.maximumNumberOfZones` | At least three on the actual created plan |
| Web App, `Microsoft.Web/sites` | Runs on the intended Linux plan with a qualified `siteConfig.linuxFxVersion`, public network access Disabled, Always On enabled, client affinity disabled for the stateless workload |
| Application instance inventory | Six baseline application instances, each with a nonempty instance ID and `physicalZone`; exactly three distinct physical zones represented |
| Application participation | Healthy application instances and observed workload responses or telemetry from all three zones before injection |
| Steady-state scaling | Begin with fixed capacity six for deterministic tests. A later autoscale profile must preserve the three-zone requirement and requalify surviving capacity. |

Preserving six workers retains the previous initial capacity decision while removing the Container Apps Dedicated D4 profile. Azure manages worker placement. Record the observed worker count per zone and measure whether the surviving workers sustain the load.

### Three-zone acceptance contract

Perform these checks before declaring deployment ready, before each test and after recovery:

1. Verify the selected region, SKU and actual App Service scale unit. A region advertising three zones can still place a plan on infrastructure with a lower zone capability.
2. Read the plan's `zoneRedundant`, `maximumNumberOfZones`, capacity and per-app scaling configuration. Require `true`, at least three zones, the approved baseline capacity and participation on the intended workers.
3. Read the Web App's actual instance inventory and its `physicalZone` values. Require three distinct, nonempty zones and the expected application-instance count.
4. Correlate each instance ID with application health and request telemetry. An empty zone, a count inferred from the plan or a claim about unseen replicas is insufficient.
5. Save UTC-stamped plan, instance, health and traffic snapshots. Treat placement as point-in-time evidence and refresh it before selecting fault targets.
6. During an injection, record the expected loss and surviving capacity. Reapply the full baseline gate after recovery.

**Apply capability verification to:** Azure Portal > App Service Plan > Scale out (App Service plan) > Maximum available zones, or `properties.maximumNumberOfZones` on that plan.

**Apply placement verification to:** Azure Portal > Web App > Health check > Instances, or the Web App `instances` REST endpoint. The documented `2024-04-01` endpoint exposes `physicalZone`; verify and pin the supported API during implementation.

An illustrative read-only request is:

```text
GET https://management.azure.com/subscriptions/{subscriptionId}/resourceGroups/{workloadGroup}/providers/Microsoft.Web/sites/{appName}/instances?api-version=2024-04-01
```

Keep actual identifiers and responses in ignored local evidence. Bicep configuration alone cannot supply this runtime inventory.

If the plan supports only two zones, zone values are missing, or the app is observed in fewer than three zones, report the unmet gate explicitly. Preserve the owned resources for diagnosis or select and qualify another capable region. Successful three-zone deployment requires actual evidence.

### Private networking and management

Retain the proven, directly peered workload and operations VNets for the first refactor. Use Azure-provided DNS and explicit private-zone links.

| Path/component | Contract |
| --- | --- |
| App Service outbound | Regional VNet Integration through a dedicated subnet delegated to `Microsoft.Web/serverFarms`; connect to PostgreSQL through its private endpoint |
| App Service inbound | Web App Private Endpoint using the provider's `sites` group; HTTPS available through the private route |
| Subnet separation | App Service integration, private endpoints and the runner use separate appropriate subnets; the integration subnet hosts no private endpoints |
| Application DNS | `privatelink.azurewebsites.net`, including the application and SCM/Kudu records needed for private publication |
| PostgreSQL DNS | `privatelink.postgres.database.azure.com`; preserve the stable server FQDN and full TLS hostname validation |
| PostgreSQL networking | Private Link-compatible server networking with Private Endpoint and public network access Disabled |
| Private operations | One lab-owned runner VM for package publication, database bootstrap, migration, probes and optional load generation |
| PC-to-runner path | Retain the previously qualified Bastion/source-transfer path initially; use local scripts for orchestration and display progress |
| VM outbound | Retain explicit NAT and required HTTPS egress where needed for bootstrap and management; VMs receive no public IP |
| Supporting services | Retain private Key Vault and the private monitoring paths actually needed by the app and tests |

Remove the Container Apps environment, Dedicated workload profile, container registry/image-pull path and Automation-specific private endpoints/DNS. Publish a versioned application package through the private deployment path.

App Service Private Endpoint provides inbound access. VNet Integration supplies the outbound path. Verify both independently:

- Private runner -> application HTTPS and SCM/Kudu.
- App Service -> PostgreSQL and required private dependencies.
- Public client -> denied application and database data-plane access.

Do not open public application or database access to work around deployment problems. The operations NAT/Bastion public IPs follow D13-D15, including finite exemption validation if still required by effective policy.

Management NAT and the single runner have their own availability limits. Keep them outside native application fault targeting and disclose any interruption to measurement. Full-zone application-path claims require independent evidence about all affected dependencies.

### PostgreSQL and regional eligibility

Retain General Purpose `Standard_D4ds_v5`, four vCores and 128 GiB as the initial database sizing. Require Ready/Healthy zone-redundant HA with distinct primary and standby zones.

Check the exact subscription/region's top-level `restricted: Disabled` and `zoneRedundantHaSupported: Enabled`. Verify App Service three-zone capability and native App Service/PostgreSQL Actions independently. The earlier Sweden Central database result supplies historical evidence; the App Service path remains unqualified there.

## 3. Demo application

Reuse the ASP.NET Core order API, Npgsql, migrations and transactional idempotency. Validate the selected supported .NET runtime on Linux App Service before publication.

| Endpoint | Contract |
| --- | --- |
| `POST /api/orders` | Client-generated operation ID, commit before acknowledgement, checksum-preserving idempotency |
| `GET /api/orders/{id}` | Durable read with original operation ID and payload checksum |
| `GET /health/live` | Local process health, independent of PostgreSQL |
| `GET /health/ready` | Bounded readiness/dependency checks |
| `GET /health/dependencies` | Authenticated diagnostic dependency status |

Use App Service's `WEBSITE_INSTANCE_ID` in response metadata and telemetry, together with run, operation and trace IDs. Correlate it with the platform's observed zone inventory. Configure App Service Health Check explicitly and avoid unnecessary coordinated process restarts during a database outage.

Keep durable business state in PostgreSQL. Reconnect using the stable FQDN, refresh managed-identity tokens and discard broken pooled connections. Preserve the five-second server-operation deadline, at most two bounded transient retries and explicit terminal errors. Client retries reuse the same operation ID for up to 180 seconds and reconcile uncertain commits.

Use separate least-privilege runtime, migration, runner and Chaos identities. Preserve authenticated business requests and private secret access; keep tokens and credentials out of source, console output and evidence. Azure Owner access does not confer Entra directory permissions. Do not perform PIM.

## 4. Experiment catalog and evidence

Open the modern Azure Chaos Studio **Workspace**, review its discovery and **Scenarios**, and select exact owned targets. Provision definitions without automatically executing them.

| Test | Injection and evidence boundary |
| --- | --- |
| BASE-001 | No fault; prove the complete private path, six active app instances across three observed zones, throughput, latency and writes |
| HA-APP-001 | Native App Service Kill process on an explicit application instance; observe routing, process recovery and surviving capacity |
| HA-APP-ZONE-001 | Native Kill process using verified zone targeting; record the instances in the selected zone and evidence of the actual effect |
| HA-DB-001 | Native PostgreSQL forced failover; observe role/zone transition, application reconnection, recovery and durability |
| HA-COMBINED-001 | Explicitly configured native application and database Actions; qualify only when their independently observed disruptive effects actually overlap |
| HA-AZ-001 | Correlated loss of a real availability zone across the relevant application path; remain BLOCKED without a supported injection and qualifying affected-zone evidence |

The documented App Service Actions are `microsoft-appservice-killprocess/1.0` and `microsoft-appservice-restart/1.0`. Kill process exposes `ProcessName`, `InstanceIds` and `Zones`. It is a discrete process-crash operation. A restart of the entire app has a separate recovery-test scope.

Validate the regional schema, canonical Action identifier, Linux/runtime support, selector semantics and permissions before deploying dependent resources. Where eligibility needs a real app, use an explicitly bounded owned-target qualification after basic readiness. Resolve physical/logical zone identifiers using supported platform evidence; do not assume that an arbitrary `Zones = ["1"]` matches an observed physical-zone label.

### Linux compatibility and Windows comparison

Linux is the selected deployment OS. The documented **Cache Stampede with Process Crash** template explicitly supports Windows App Service only. That template combines Redis, MySQL and an App Service process crash; its OS restriction does not by itself establish the support of a custom App Service/PostgreSQL Scenario or every individual App Service Action.

The Action catalog lists Kill process, Restart and instance/zone selectors. The OS eligibility of the selected Linux Action/runtime/selector combination still requires evidence. Keep this distinction in the [compatibility matrix](research.md#linux-baseline-and-windows-test-coverage).

For each application test, record the OS/runtime, Action/schema, selector, eligibility evidence, actual effect and verdict. If Linux is unsupported, report BLOCKED with the exact source/provider reason and document whether Windows has a supported equivalent. An absent Linux support statement alone establishes an unqualified capability; it does not prove a Windows-only Action.

Test the selected Linux/native implementation and report supported-test results individually. A required application or combined test that lacks qualifying evidence leaves the full suite incomplete. Any changed implementation is recorded and requalified against the requested test semantics.

A zone-selected process crash exercises application failure effects on those instances. It does not establish a sustained infrastructure-zone outage. The former five-minute Container Apps readiness-withdrawal adapter is superseded; no custom runbook or new application fault-control route is required by this initial native-Action design.

Use the exact PostgreSQL target, forced failover, no automatic failback and no skipped ineligible servers. Resolve serialized values and canonical identifiers from the pinned regional schema. Require at least twenty minutes between failovers and a Healthy standby.

Give the Workspace discovery identity Reader on the owned discovery scope and execution permissions on its exact application/database targets. The deterministic suite records those exact targets.

## 5. Workload, procedure, and measurements

Preserve the open-arrival-rate k6 workload: twenty business operations per second, 80% reads and 20% writes, plus a separate one-second authenticated read/write canary.

1. Run explicit preflight: private DNS, application and SCM access, authentication, three-zone placement, database HA, capacity, monitoring and exact fault targets.
2. Warm up for five minutes and establish a ten-minute baseline. A failed baseline prevents injection.
3. Start the selected Scenario under the current suite authorization. Save request, acceptance and observed-effect timestamps separately.
4. Measure native process crashes as discrete events. For app-only faults, record at least five minutes of post-effect observation; this replaces the previous five-minute held-readiness fault.
5. Observe database or combined recovery for at least ten minutes after injection, extending observation to obtain a continuous five-minute stable post-fault period.
6. Re-read all unique issued writes, resolve uncertain outcomes, verify acknowledged-write checksums and recapture app placement/database HA.
7. Cancel or reconcile any remaining test effects and save the report. Leave infrastructure running for the operator's subsequent tests or manual deletion.

| Measure | Target |
| --- | --- |
| Normal three-zone placement | Six active application instances across three observed physical zones, with participation/health evidence |
| Baseline and stable post-fault success | At least 99.9% successful business operations |
| Baseline and stable post-fault latency | Successful-operation p95 at most one second |
| Application-crash-only success | At least 99% during the five-minute post-effect observation |
| Application-crash-only latency | Successful-operation p95 at most two seconds |
| Application-crash-only complete unavailability | No interval longer than five seconds with all business canary operations failing |
| Database or combined recovery | At most 180 seconds to the beginning of a qualifying sixty-second recovery window |
| Recovery window | At least 99% canary and business-operation success, complete expected samples, successful-operation p95 at most one second |
| Data integrity | Zero lost acknowledged writes, duplicate logical writes or checksum mismatches; every issued write resolved |
| Operational recovery | Automatic application recovery without manual restart, endpoint change or database repair |
| Privacy | Authorized private clients succeed; public data-plane clients are denied |

Report full-phase availability independently of the recovery verdict. A PASS against the 180-second database recovery objective can coexist with a FAIL against full-phase availability; neither establishes near-zero interruption.

Count failed responses, timeouts, transport failures and dropped scheduled operations explicitly. Record raw HTTP attempts, logical business operations and canaries separately. A write succeeds after its commit is established by acknowledgement/reconciliation.

Use UTC ISO timestamps without losing offset or fractional precision. Preserve original raw events and distinct `PASS`, `FAIL`, `BLOCKED` and `INCONCLUSIVE` verdicts. Missing preconditions block injection; missing evidence after execution prevents a conclusive PASS. Disclose client saturation and measurement-path failures.

## 6. Manual test execution

Use deterministic, individually selected Scenarios first. Random campaigns, unattended scheduling and lifecycle controllers are outside the current scope.

The PC starts and observes control-plane operations; Azure executes the native Chaos Actions. Loss of the PC session can interrupt observation without stopping an accepted Action. Document cancellation and actual-effect reconciliation, preserve partial reports and apply database cooldowns.

There is no independent 24-hour suspension or deletion guarantee in this architecture. A local `finally` block and a resource expiry tag cannot supply one. Keep that operational responsibility explicit.

## 7. Repository and automation deliverables

| Location | Responsibility after refactoring |
| --- | --- |
| `infra/` | App Service Plan/Web App, private integration/endpoints/DNS, PostgreSQL, required support services, one runner and modern Chaos definitions |
| `src/` | Order API, migrations, instance-aware telemetry and application tests |
| `scripts/` | Local, bounded deployment/bootstrap/readiness steps with visible progress and no automatic test or deletion chain |
| `tests/` | Local regressions, explicit measurement/evidence helpers and native fault acceptance |
| `config/` | Publishable templates/defaults; no real environment identifiers |
| `.local/` and `.azure/` | Ignored private context, manifests, raw evidence, logs and deployment validation |

Record source revision/package hash, region, exact owned resources, native Scenario/Action identifiers, app instance/zone snapshots, role transitions, phase boundaries, errors, dropped operations, latency and write verification. Keep partial results when a step fails.

The active `Build-Lab.ps1` now implements the staged private App Service deployment; historical lifecycle/cycle entrypoints remain inert. `Test-Lab.ps1` implements individually selected baseline/native cases with fail-closed readiness and evidence gates. Its native effect orchestration remains unqualified end-to-end; the [execution results](app-service-results.md) record current capabilities and blockers.

## 8. Lab lifecycle commands

The active workflow is **deploy -> operator-selected tests -> operator-managed deletion**.

### Deployment from the PC

Validate the approved account, tenant/subscription, region, policies, Action catalog and exact lab scope. Create a fresh ownership manifest, perform guarded previews and retain per-step timings. Verify the actual plan's three-zone capability early, before expensive dependent bootstrap.

Provision the private paths, publish a versioned application package through the runner, bootstrap PostgreSQL identities/migrations and perform non-destructive readiness checks. Stream available local/remote step output and save logs. Identify any guest/API output that is buffered; do not claim live streaming for a buffered channel.

On failure, exit explicitly, retain successful owned resources and print the failed step and evidence location. No fault injection, resource-group deletion or retry loop that changes architecture may follow automatically.

### Manual deletion

Show the exact owned groups and resource dependencies so the operator can delete them. The retained topology's dependency order is workload -> operations -> network. Do not expand scope to shared/provider-created resources.

Disclose recoverable Key Vault objects, mandatory PostgreSQL backup retention and Azure audit retention. A successful group-delete request alone cannot certify complete cleanup or purge. The operator owns final verification and any explicitly chosen purge. Keep the approved local environment and evidence unless the operator chooses their removal.

The old Destroy, Suspend/Resume, automatic-cycle and controller contracts are superseded. Their historical code and results remain accessible through Git.

## 9. Implementation gates

1. Complete documentation correction; distinguish current requirements from historical Container Apps evidence.
2. Refactor source and regression tests without deploying the old architecture.
3. Verify current App Service native Actions, Linux runtime/selector support, plan/scale-unit three-zone capability, private SCM publication, VNet Integration and PostgreSQL HA eligibility. Document evidenced Windows alternatives.
4. Compile/validate Bicep and inspect exact-owned effective previews. Verify required exemptions and repair absence/expiry before continuing.
5. Deploy only after the agreed implementation scope is ready. Require three-zone runtime evidence and both private network paths before readiness.
6. Execute each requested Chaos Scenario under the current authorization. Report every acceptance gate independently.

The previous cycle's 38.624-second recovery and 3,558 retained acknowledged writes describe the earlier Container Apps/PostgreSQL run. They supply no App Service or three-zone application qualification. Its final manual group deletion remains operator-verified.

## 10. Boundaries

Keep subscription/tenant IDs, real group names, accounts, authentication paths, policy details, secrets and raw evidence out of publishable sources. Use ignored local configuration and run the publication guard before commits or publication.

Preserve exact ownership, unrelated resources and independently verified Azure authentication/authorization, effective policy, platform capabilities and evidence. Current operating authorization is defined in [implementation contracts](implementation-contracts.md).

The [earlier architecture guide and diagrams](architecture-guide.md) describe the superseded Container Apps/controller design until explicitly redrawn. The current specification and D17-D19 control the App Service refactor.

### Official platform references

- [App Service zone redundancy, maximum zones and observed physical-zone inventory](https://learn.microsoft.com/en-us/azure/app-service/configure-zone-redundancy)
- [Reliability in Azure App Service](https://learn.microsoft.com/en-us/azure/reliability/reliability-app-service)
- [App Service VNet Integration](https://learn.microsoft.com/en-us/azure/app-service/overview-vnet-integration)
- [App Service private endpoints](https://learn.microsoft.com/en-us/azure/app-service/overview-private-endpoint)
- [Chaos Studio Workspaces supported resources and Actions](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-workspaces-supported-resources)
- [Modern Scenarios and process-crash template limitations](https://learn.microsoft.com/en-us/azure/chaos-studio/chaos-studio-scenarios)
