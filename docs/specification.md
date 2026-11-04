# Implementation specification

Defines the lab requirements, architecture, test contracts, and lifecycle operations. Apply the [accepted decisions](../DECISIONS-ACCEPTED.md) and validate the platform prerequisites before deployment.

## 1. Objective and requirements

Build a repeatable lab that measures whether an application continues operating, or recovers automatically within an agreed limit, when availability-zone capacity is lost.

| ID | Requirement |
| --- | --- |
| R1 | Host the demo application on Azure Container Apps. |
| R2 | Store application data in Azure Database for PostgreSQL Flexible Server. |
| R3 | Deploy in one Azure region with three availability zones and enable supported zone redundancy throughout the application path. |
| R4 | Test the effect of losing one availability zone on the complete application. Preserve a clear distinction between simulated effects and a verified zone outage. |
| R5 | Provide modular Bicep, demo application source, deployment automation, deterministic tests, and guarded random-chaos automation. |
| R6 | Use VNet integration, private endpoints, private DNS, TLS, managed identities, and NSGs. Keep networking focused on Chaos/HA testing; omit Azure Firewall and a dedicated hub. |
| R7 | Produce independently measured availability, recovery, latency, and data-integrity results. |
| R8 | Provide single-command build and destroy operations for a complete lab lifecycle, and suspend and resume operations for a data-preserving lifecycle. |
| R9 | Start automatic suspension 24 hours after successful build or resume, without depending on an active operator session. |
| R10 | Create all lab infrastructure from scratch, including its network and management components, and delete it through the destroy command. |
| R11 | Use Azure-allocated Standard static IPv4 for operations NAT/Bastion public IPs. Exclude BYOIP, IP prefix resources, supplied public addresses, public-IP `ipTags`, and dependency on `AllowBringYourOwnPublicIpAddress`. |

### Architecture baseline

- Use managed PostgreSQL zone-redundant HA. Its customer-configurable topology places the primary and standby in different zones. Azure also documents a service-managed WAL replica for commit quorum.
- Treat three-zone deployment as a regional application architecture. Explicit placement of three full PostgreSQL nodes is outside this topology.
- Use 180 seconds as the recovery objective for database-dependent business operations. PostgreSQL failover can interrupt connections and requests.
- Begin with supported database failover and application replica-loss simulations. Require a supported method establishing correlated loss of a real zone before making the complete zone-outage claim.

Validate regional capabilities before deployment. The selected availability objective allows bounded interruption during failover.

## 2. Target architecture

See the [private architecture diagram](diagrams/README.md#1-private-architecture) for the network, private endpoints, managed services, and ownership boundaries.

### Regional topology

Use an isolated non-production subscription or landing-zone subscription with separate resource groups for networking, workload, and test control.

Use the provided subscription with Owner access. Select a policy-allowed region with verified subscription-level PostgreSQL zone-redundant HA eligibility; D16 selects Sweden Central for the current retry. D05's historical `westeurope` default remains subject to that preflight. Use workload `10.81.0.0/16` and operations `10.82.0.0/16`, directly peered in both directions. Parameterize these ranges, check for overlap, and fail preflight if required regional capabilities are unavailable. All lab network and management resources belong to the destruction scope.

Check the PostgreSQL location-capabilities response's top-level `restricted` and `zoneRedundantHaSupported` fields for the exact subscription and selected region. Require `Disabled` and `Enabled`, respectively; SKU-level `supportedHaMode` alone does not establish eligibility. Propagate region consistently to DNS, service tags, application/controller resources and cleanup.

| Component | Required configuration |
| --- | --- |
| Private networking | Two VNets with direct bidirectional peering and Azure-provided DNS. The network resource group holds private DNS zones/links and two NAT/Bastion public IPs; no hub VNet, Azure Firewall, DNS proxy, or firewall-directed route table. |
| Workload VNet | Separate Container Apps integration and private-endpoint subnets. Use Container Apps managed outbound connectivity. |
| Operations VNet | Private build/load runner, two lifecycle workers, private endpoints, and Bastion subnet `10.82.2.0/26`. Keep operations resources outside application fault targeting. |
| Operations outbound access | Explicit Standard NAT Gateway and Azure-allocated public IP on the private VM subnet; `defaultOutboundAccess=false`. No unsolicited Internet inbound access. |
| Container Apps environment | Workload profiles environment; VNet integrated; `properties.vnetConfiguration.internal = true`; `properties.zoneRedundant = true` at creation; `properties.publicNetworkAccess = Disabled`; environment private endpoint. App ingress remains `external = true` for private clients outside the app environment. |
| Demo container app | Stateless API; single active revision during each test; six minimum replicas and twelve maximum replicas as initial sizing. |
| Compute capacity | Dedicated D4 profile with at least three nodes. Verify placement behavior, quota, and surviving capacity. |
| PostgreSQL | General Purpose `Standard_D4ds_v5`, four vCores, 128 GiB storage; zone-redundant HA; distinct primary and standby zones; private endpoint; public network access disabled. |
| Container registry | ACR Premium, private endpoint, public network access disabled, managed-identity image pulls, and verified regional zone resilience. |
| Key Vault | Private endpoint; public network access disabled; RBAC; mandatory soft delete; purge protection disabled for lab cleanup. Store only credentials or certificates that remain necessary. |
| Monitoring | Log Analytics and workspace-based Application Insights; Azure Monitor Private Link Scope for supported private ingestion and query paths; diagnostic settings on relevant resources. |
| Test artifacts | Lab-owned private Blob Storage with zone redundancy, public access disabled, and identity-based access. Avoid optional immutability or retention that prevents teardown. |
| Chaos control | Azure Chaos Studio Workspace and custom Scenarios. Deploy only the actions and permissions required by the approved test catalog. |
| Lifecycle control | Private Azure Automation account, managed identity, one-time suspension schedule, hourly reconciliation, private control store, and two extension-based Hybrid Runbook Worker VMs in different zones. Keep this management path available during suspension and delete it last. |

Measure capacity before final sizing. At the selected load, surviving replicas and compute nodes must handle the expected loss of one zone without depending on immediate scale-out.

### Network paths

1. Lab-created private runners reach the application through its Container Apps environment private endpoint.
2. The Container Apps integration subnet provides outbound network access to PostgreSQL, ACR, Key Vault, and private telemetry endpoints.
3. Container Apps uses managed outbound connectivity; private VMs use the operations NAT Gateway. Remove appliance-directed default routes and custom DNS forwarding. Preserve platform-exempt Azure DNS without an explicit `AzurePlatformDNS` NSG rule. NSGs allow required platform access, private HTTPS/PostgreSQL and outbound Internet HTTPS for bootstrap; deny other outbound traffic. FQDN-based outbound filtering and inspection are outside this lab's acceptance scope.
4. Private-endpoint traffic follows the approved private route. Inspect it only where supported routing and private-endpoint network policies have been explicitly configured.
5. Administrative connectivity uses Bastion in the operations VNet. Private runner/worker VMs have no public IP addresses. No pre-existing VPN, ExpressRoute, hub, or private runner pool is required.

Peer the two VNets directly and verify both directions. Private endpoint and application traffic uses direct private routing. Azure Firewall inspection is excluded.

The Standard management NAT Gateway is a single-zone egress dependency. Worker placement alone does not establish management-path survival of a real-zone outage. Record this limitation separately from application-path HA.

### Public-IP allocation contract

Apply [D13](../DECISIONS-ACCEPTED.md#d13-azure-allocated-public-ips-without-byoip) to the lab network module and every effective deployment preview:

| Resource/property | Required value or rule |
| --- | --- |
| Operations NAT/Bastion `Microsoft.Network/publicIPAddresses` | Two addresses in the dedicated network group, referenced by operations resources |
| `sku.name` | `Standard` |
| `properties.publicIPAllocationMethod` | `Static`; Azure selects the address |
| `properties.publicIPAddressVersion` | `IPv4` |
| `properties.ipAddress` | Omit on creation; never request a particular address. Preserve an existing Azure-assigned address when returned by an update preview. |
| `properties.publicIPPrefix`, `properties.customIPPrefix` | Omit |
| `properties.ipTags` | Omit in templates; effective payload must contain no IP tags, including `FirstPartyUsage` |
| `Microsoft.Network/customIPPrefixes`, `Microsoft.Network/publicIPPrefixes` | Excluded |
| `Microsoft.Network/AllowBringYourOwnPublicIpAddress` | No dependency, registration, or required registration-state lookup |

Lab ownership metadata belongs to the resource's top-level `tags`. Public-IP `properties.ipTags` has a separate platform meaning.

Validate the effective payload after inherited Azure Policy effects. A syntactically valid template or successful ARM validation is insufficient for this contract. Reject an incompatible policy-adjusted payload before issuing the resource deployment and report `BLOCKED: public-IP policy incompatibility`.

An observed inherited append policy added `FirstPartyUsage=/Unprivileged` to applicable public IPs. Exact governance identifiers belong only in ignored local evidence. Omitting the tag, specifying an empty array, or changing the API version left that policy applicable. Preserve the governance boundary and stop on incompatible effective payloads; feature registration is excluded.

The inspected rule and assignment contained no resource-group tag exclusion. Do not guess a key/value or apply a tag as an exclusion without matching the actual applicable condition. A verified rule-supported exclusion may be used on new lab groups. The operator separately authorized the temporary exemption defined in [D15](../DECISIONS-ACCEPTED.md#d15-temporary-lab-only-public-ip-policy-exemption): one initiative member, only the dedicated network group, only public-IP resources, 24-hour expiry and default assignment-scope validation. Inherited definitions/assignments and other rules remain unchanged.

Keep the exact exemption identifiers, ownership manifest and raw verification in ignored `.local/policy-exception/`. Verify expiry and effective payload before provisioning; retain D13 as the fail-closed deployment gate. Explicitly inventory group-scoped policy exemptions because generic resource enumeration can omit them. Continue with the preparation manifest when its owned network group already exists; cleanup deletes that owned group and its exemption.

Persist required exemption contracts in the ignored environment file's `requiredPolicyExemptions` array (`id`, `assignmentId`, singleton `referenceIds`), independently of run manifests. Startup reads the live Azure exemption and checks its finite `expiresOn`, exact assignment/member, `Waiver` category and public-IP selector. Build, cycle and operator Resume stop before mutations when an exemption is missing, expired or changed. Every group deployment repeats the check. Warn when expiry is less than two hours away. A blocked cycle preflight must preserve existing resources and must not invoke cleanup.

The blocking message identifies the exemption and resource group and instructs the operator to obtain approval, create a new scoped exemption or extend `expiresOn` in Azure **Policy > Exemptions**, record the contract in the local environment and owned manifest, and revalidate. Never renew automatically. Cleanup remains available after expiry. Retain the environment contract after destruction so the next start detects that the group/exemption needs preparation again. `tests/Test-PolicyExemptions.ps1` verifies active, expired, missing, near-expiry and changed-contract cases without Azure writes.

Apply the simplified D14 topology and preserve all private data-plane acceptance tests. NAT and Bastion still require ordinary Azure public IPs and the same effective-policy validation.

### Service-specific configuration

**Container Apps:** place the environment infrastructure in a dedicated subnet delegated to `Microsoft.App/environments`. Reserve growth headroom beyond the documented minimum subnet size. Place private endpoints in a separate subnet.

The app must accept ingress from outside its Container Apps environment so that private-endpoint clients can reach it. At app scope, `configuration.ingress.external = true` supplies that route. Environment-level public network access remains disabled. Verify that an Internet client cannot reach the application.

**PostgreSQL:** create the server using the Private Link-compatible networking model and disable public network access. Connect through its private endpoint. PostgreSQL delegated-subnet VNet integration and Private Link are separate deployment options; this specification selects Private Link. Container Apps supplies the required workload VNet integration.

**DNS:** use Azure-provided DNS and private DNS zone groups. Link every required zone directly to both VNets. No custom DNS server or forwarding appliance is deployed.

| Service | Private DNS requirement |
| --- | --- |
| Container Apps | `privatelink.<region>.azurecontainerapps.io` |
| PostgreSQL | `privatelink.postgres.database.azure.com` |
| ACR | `privatelink.azurecr.io`, including required registry data-endpoint records |
| Key Vault | `privatelink.vaultcore.azure.net` |
| Blob Storage | `privatelink.blob.core.windows.net` |
| Azure Monitor | Complete AMPLS DNS zone set for the selected ingestion and query paths |
| Azure Automation | Private endpoints and DNS for the selected Hybrid Runbook Worker communication paths |

Preserve service FQDNs and TLS hostname validation. Never configure a database connection with a private-endpoint IP address.

### Enterprise security baseline

- Use separate managed identities for application runtime, migrations, deployment, load generation, and chaos control.
- Authenticate application clients with Microsoft Entra ID. Validate issuer, audience, and application roles.
- Use PostgreSQL Entra authentication with automatic token renewal. Grant the runtime identity only required SQL privileges; use a separate migration identity for DDL.
- Require TLS 1.2 or higher where configurable and validate server certificates.
- Disable ACR admin credentials, anonymous storage access, and storage shared-key access.
- Use federated CI credentials. Keep secrets, tokens, and database contents out of logs and source control.
- Validate Microsoft Entra directory permissions separately from subscription Owner access. Bootstrap new lab-owned registrations automatically when authorized; otherwise require tenant authorization or administrator bootstrap with recorded ownership and cleanup permissions.
- Apply least-privilege RBAC at the smallest supported scope. Protect management networking, DNS, identities, backups, and monitoring from chaos actions.
- Deny unapproved Internet egress. Maintain a versioned destination/port/reason inventory for required exceptions.
- Run containers as non-root, drop unnecessary capabilities, and use a read-only root filesystem where supported. Reserve writable ephemeral storage only for documented needs.
- Scan images and dependencies. Deploy immutable image digests and record them in reports.
- Apply Azure Policy, resource tags, operational diagnostics, and Defender for Cloud settings. Fail preflight if inherited policy prevents the selected disposable-lab configuration.
- Use PIM and an audited break-glass procedure for privileged administration.
- Create the isolated Key Vault with `enablePurgeProtection` omitted: the API rejects explicit `false` and omission leaves protection unenabled. Verify the live property before accepting cleanup feasibility. Preserve other security controls and purge the deleted vault explicitly during teardown.

The private-network requirement applies to application and data-plane access. Azure management and identity calls use their supported endpoints with authenticated, allowlisted egress. Inventory service-managed diagnostic delivery separately from application telemetry; prove that required logs still arrive with the selected public-access restrictions.

## 3. Demo application

Reference implementation: ASP.NET Core on the supported .NET LTS selected at implementation, Npgsql, and OpenTelemetry. Pin runtime and dependency versions in the repository.

Implement a small order API with durable writes and read-after-write verification.

| Endpoint | Behavior |
| --- | --- |
| `POST /api/orders` | Accept a client-generated operation ID and payload. Commit before acknowledging success. |
| `GET /api/orders/{id}` | Return the committed order, payload checksum, and operation ID. |
| `GET /health/live` | Check local process health without querying PostgreSQL. |
| `GET /health/ready` | Check readiness with bounded dependency checks. Temporary database failure must not trigger liveness restart loops. |
| `GET /health/dependencies` | Return authenticated dependency status for diagnostics. |

Application rules:

- Keep all durable business state in PostgreSQL.
- Enforce a unique operation ID and transactional idempotency. Repeating an operation with the same payload returns the same committed result; a conflicting payload returns an explicit conflict.
- Reconnect through the stable PostgreSQL hostname after failover. Refresh identity tokens and discard broken pooled connections.
- Retry transient failures with bounded exponential backoff and jitter. Initial server request deadline: 5 seconds; use at most two retries within that deadline.
- The test client may retry a logical write for up to 180 seconds using the same operation ID. Measure each HTTP attempt separately.
- Return explicit errors when retries expire. A queued or in-memory write cannot count as a committed success.
- Separate startup, readiness, and liveness probes. Emit replica ID, revision, run ID, operation ID, and trace ID.
- Apply schema migrations as a controlled deployment step before traffic starts.
- Package replica fault controls only in the lab build. Require explicit lab enablement and authorized management execution; expose no public chaos route.

## 4. Experiment catalog and evidence

The [HA test dynamics diagram](diagrams/README.md#2-ha-test-dynamics) connects the injection sequence, recovery behavior, acceptance thresholds, and random-chaos guards.

The initial hypothesis is that losing one zone preserves data and allows the application to remain within its approved availability objective.

| Test | Injection | Evidence and boundary |
| --- | --- | --- |
| BASE-001 | No fault; steady workload | Establish throughput, latency, successful writes, and replica/HA readiness. |
| HA-DB-001 | PostgreSQL forced failover through Chaos Studio | Measure business recovery, reconnection, role transition, and data integrity. Covers database failover behavior. |
| HA-APP-001 | Withdraw two of six ready app replicas for five minutes | Measure routing and surviving capacity. Replica selection has no asserted availability-zone identity. |
| HA-COMBINED-001 | Hold the two-replica withdrawal while forcing PostgreSQL failover | Measure recovery under correlated capacity and database disruption. Record actual overlap. |
| HA-AZ-001 | Verified loss of a selected real zone across the application path | Full-zone validation. Require a supported injection method and affected-zone evidence; otherwise classify the test as `BLOCKED`. |

### Fault implementation requirements

Use the Workspaces resource model. Its preview use and relevant advanced features are authorized for the lab. Document preview dependencies and execute the preview validation suite before claiming verified behavior.

For HA-DB-001, use the PostgreSQL action `microsoft-azurepostgresql-failover/1.0`, with `FailoverMode = ForcedFailover`, `RestoreOnStop = false`, and `SkipIneligibleServers = false`. Validate the deployed regional action schema before use. Target only the intended HA server through explicit resource filtering and a reviewed target inventory.

Avoid automatic failback at action completion. Wait at least 20 minutes between failovers and require the standby to be healthy before another operation. Returning to the original primary is a separate approved planned failover.

For HA-APP-001, implement a lab-only local fault helper invoked against explicit replica IDs through authenticated Container Apps management execution. It causes readiness failure for a bounded TTL while leaving the process alive. Confirm traffic withdrawal and the actual number of affected replicas.

Prototype the non-interactive execution path before committing to this adapter. If that path is unavailable, report the test as `BLOCKED` and revise the adapter. Scaling down an app does not establish targeted zone loss. A future process-crash test must be labeled separately from readiness withdrawal.

## 5. Workload, procedure, and measurements

### Initial workload

- Use k6 with an open arrival-rate model: 20 business operations per second, 80% reads and 20% writes.
- Create synthetic records before the run. Use unique run and operation IDs.
- Run a separate authenticated read/write canary once per second.
- Maintain a client-side journal of issued writes, every HTTP attempt, acknowledgements, retry outcomes, and expected checksums.
- Count timeouts, dropped scheduled operations, transport failures, and non-success responses as failures.
- Keep load constant across phases. Record any load-generator saturation.

### Run sequence

1. **Preflight:** verify private DNS, connectivity, authorization, HA readiness, distinct PostgreSQL zones, replica count, capacity, approved targets, and monitoring.
2. **Warm-up:** run for five minutes; exclude this phase from acceptance calculations.
3. **Baseline:** run for ten minutes. Abort injection if baseline criteria fail.
4. **Injection:** record request, acceptance, and observed-effect timestamps. Apply the selected fault while load continues.
5. **Observation:** hold replica withdrawal for five minutes. Database failover is a role transition; measure its actual disruption independently of the Scenario's configured duration.
6. **Recovery:** observe for at least ten minutes after injection. Extend the run if needed to establish a continuous five-minute stable post-fault window.
7. **Verification:** reconcile every write against PostgreSQL and capture final HA, replica, DNS, and control state.
8. **Cleanup:** expire fault controls, cancel remaining runs, restore temporary configuration, verify health, and persist the report.

For HA-COMBINED-001, verify that replica withdrawal is active before requesting failover. At least part of the observed database disruption must overlap the replica withdrawal; otherwise the combined test is inconclusive.

### Acceptance criteria

The following accepted targets describe application behavior under the stated load.

| Measure | Target |
| --- | --- |
| Baseline and stable post-fault operation success | At least 99.9% successful business operations in each applicable window |
| Baseline and stable post-fault latency | Successful-operation p95 at most 1 second |
| Replica-withdrawal-only success | At least 99% throughout the five-minute injection |
| Replica-withdrawal-only latency | Successful-operation p95 at most 2 seconds |
| Replica-withdrawal-only complete unavailability | No interval longer than 5 seconds with all business canary operations failing |
| Database or combined recovery | At most 180 seconds from observed database disruption to the start of a qualifying recovery window |
| Qualifying recovery window | 60 consecutive seconds with at least 99% business-operation success and successful-operation p95 at most 1 second |
| Data integrity | Zero lost acknowledged writes, duplicate logical writes, or payload/checksum mismatches |
| Operational recovery | Automatic application recovery; no manual restart, endpoint change, or database repair |
| Private access | Authorized private clients succeed; Internet data-plane access fails |
| Cleanup | No active fault lease, unexpected resource modification, or unreported unhealthy state |

If no disruption is observed, report a zero observed recovery duration only when the independent evidence confirms that failover actually occurred.

Record outage intervals at one-second canary resolution and all recovery timestamps in UTC. Report p95 for successful operations alongside errors and timeouts. Include raw-attempt success and eventual logical-write completion as separate measures.

Any write whose commit outcome was unknown after a timeout must be reconciled using its operation ID. Every issued write must finish with a known committed or confirmed absent outcome; unresolved outcomes prevent a pass.

The HA-AZ-001 verdict additionally requires proof of a correlated real-zone outage. Passing the component tests cannot close that evidence gap.

### Advanced and preview feature validation

Maintain a feature inventory with service, feature, GA/preview classification, API/SDK version, documentation source, region, limitations, and associated test IDs. Authorization to use a feature must remain separate from evidence that its tests passed.

| Test | Required verification |
| --- | --- |
| PREVIEW-001 | Discover the regional Workspaces Action catalog and validate the pinned API and PostgreSQL parameters. Reject unsupported schema or actions. |
| PREVIEW-002 | Provision, read, and update the Workspace and Scenario through Bicep; verify identity, exact target scope, and private workload integration. |
| PREVIEW-003 | Execute PostgreSQL forced failover under load; assert the recovery, reconnection, and write-integrity criteria. |
| PREVIEW-004 | Cancel a run and reconcile actual effects. Verify guard rejection of foreign targets and failure on insufficient permissions. |
| PREVIEW-005 | Verify telemetry, partial-failure reporting, lifecycle interaction, and deletion of preview resources. |

Add dedicated tests for every additional selected preview. Treat unsupported or failed advanced features as explicit failed or blocked validations; preserve required HA and security behavior. Pin a working version only after evidence supports it.

## 6. Random-chaos controller

Provide a Chaos Monkey-inspired scheduler that selects from a versioned, allowlisted fault catalog.

- Default to dry-run and disabled scheduling until deterministic and preview tests pass.
- Require explicit subscription, resource group, resource-ID allowlist, lab tags, allowed UTC execution window, expiry, and run limits.
- Use a seeded random generator. Persist the seed, catalog version, eligible candidates, selected targets, and realized schedule. Replay the recorded plan when topology has changed.
- Allow readiness withdrawal, PostgreSQL forced failover, and an explicitly configured combined scenario.
- Permit one active scenario at a time. Combined scenarios define their grouped effects explicitly. Replica withdrawal affects at most one third of the ready replicas and must leave at least four ready replicas.
- Apply independent locks for target resources and PostgreSQL failover cooldown. Recheck health immediately before injection.
- Bound each campaign by duration, number of events, fault TTL, and an independent watchdog.
- Stop new injections when baseline health fails, an availability objective is exceeded, telemetry disappears, private access changes unexpectedly, or data verification fails.
- Provide cancellation and an emergency stop. Cancellation must verify the actual fault state.
- Keep fault TTL and recovery behavior effective if the controller crashes. Persist an action ledger outside the application database and support reconciliation on restart.
- Never select hub networking, private DNS, identities, backup stores, artifact storage, monitoring, runners, or production resources.
- Allow campaigns within the active UTC lab lease, with at most ten events and sixty minutes per campaign. Randomize spacing between five and fifteen minutes while preserving fault cooldowns.
- Run configured lab-only campaigns after deterministic and preview tests pass. No further feature approval is required. Automatic suspension inhibits new events and cancels campaigns at the lease deadline.

Stopping a database failover cannot reverse an already completed promotion. Reconcile actual role and standby state before considering any later failback.

## 7. Repository and automation deliverables

Provide the following repository structure.

| Path | Responsibility |
| --- | --- |
| `infra/main.bicep`, `infra/modules/` | Network, private DNS/endpoints, identities, workload, database, monitoring, artifacts, and Chaos resources |
| `infra/parameters/` | Lab parameters, network address ranges, sizing, and approved region; no secrets |
| `src/Demo.Api/`, `src/Demo.Api.Tests/` | API, local fault helper, migrations, container build, and application tests |
| `tests/load/` | k6 scenarios, canaries, and write-journal verification |
| `tests/resilience/` | Deterministic definitions and machine-readable assertions |
| `chaos/` | Fault catalog, seeded scheduler, target guards, watchdog, and recovery ledger |
| `scripts/` | PowerShell lifecycle entry points, preflight, test execution, and evidence export |
| `config/` | Lifecycle configuration: lab ID, subscription, region, network ownership, parameter paths, 24-hour lease, and local state/output location; no secrets |
| `.github/workflows/` | Validation and private-runner deployment/test workflows with federated authentication |

Deployment must be repeatable and parameterized. Separate provisioning, image publication, database bootstrap, migration, and test execution. Export resource IDs and private FQDNs without credentials.

The workflow must bootstrap lab-owned private runners before publishing images or connecting to the database. Public hosted runners cannot perform private data-plane steps without the lab-created network path.

### Required run outputs

Produce a JSON report, concise Markdown summary, JUnit XML, and raw measurements. Record:

- Run ID, code revision or source checksum, image digest, parameters, region, resource IDs, and target inventory.
- Seed and realized random plan, where applicable.
- Phase boundaries, fault timestamps, Scenario/action results, and controller errors.
- Replica counts, observed database role/zone transition, error rates, outage intervals, recovery duration, and latency percentiles.
- Write reconciliation, private-connectivity checks, cleanup results, and evidence limitations.
- Final status: `PASS`, `FAIL`, `BLOCKED`, or `INCONCLUSIVE`. Missing preconditions produce `BLOCKED`; missing evidence after execution produces `INCONCLUSIVE`.

Exit with a nonzero status for every outcome other than `PASS`. Preserve partial reports when execution fails.

## 8. Lab lifecycle commands

The [lab lifecycle diagram](diagrams/README.md#3-lab-lifecycle) shows the state transitions, independent private control, and complete teardown boundary.

Provide four PowerShell entry points. Each operation runs end to end from one command after authentication and configuration. The following commands define the required interfaces.

```powershell
.\scripts\Build-Lab.ps1 -ConfigPath .\config\lab.json
.\scripts\Destroy-Lab.ps1 -ConfigPath .\config\lab.json -ConfirmLabId "lab-dev01"
.\scripts\Suspend-Lab.ps1 -ConfigPath .\config\lab.json
.\scripts\Resume-Lab.ps1 -ConfigPath .\config\lab.json
```

The configured lab ID must match `-ConfirmLabId`. All commands support a non-mutating `-WhatIf` plan.

### Two lifecycle modes

| Mode | Sequence | Data and configuration | Operational objective |
| --- | --- | --- | --- |
| Complete lifecycle | Build, use, destroy | Create a fresh lab, then delete lab-owned resources, purgeable recoverable objects, and temporary local state | Verify customer-controlled cleanup and report mandatory Azure-managed remnants |
| Data-preserving lifecycle | Suspend, resume | Preserve business data, images, identities, private networking, and required configuration | Stop or deallocate every safely stoppable lab-owned resource |

Never use suspend or resume to delete and recreate the database. All created infrastructure is lab-owned; unrelated subscription and tenant resources remain outside the mutation scope.

### Build from scratch

`Build-Lab.ps1` must:

1. Validate authentication, subscription Owner access, separate directory permissions, configuration, tooling, resource providers, quotas, policies, and regional support before creating resources.
2. Allocate a unique deployment-instance ID, new dedicated resource groups, and a lab ownership manifest. On reruns, verify that recorded groups contain no foreign resources.
3. Provision the two directly peered VNets, operations NAT/Bastion, private DNS links, NSGs, and private runners. Record every created resource and attachment.
4. Deploy the Bicep modules, identities, private endpoints, registry, PostgreSQL HA, observability, artifact storage, and Chaos definitions.
5. Build and publish the demo image through the private runner, create database principals, apply migrations, and deploy the app. Perform all bootstrap steps automatically.
6. Verify private image pulls, authentication, business read/write operations, HA readiness, replica capacity, telemetry, and Internet data-plane denial.
7. Save a machine-readable manifest, operation log, and endpoint summary in the lab control store and an access-controlled local per-lab directory.
8. Arm and verify the independent suspension schedule for 24 hours after successful readiness. Provision an initial deadline with the first resources so that a partially failed build is also covered.

Require only documented prerequisites: the Owner-access subscription, authenticated operator or federated CI identity, required tenant authorization or administrator bootstrap, configuration, and listed tools. Build must not depend on a pre-existing lab network, runner, registry, database, or manually created SQL principal.

A rerun reconciles resources belonging to the same deployment instance. It must not overwrite another lab or erase an existing database. After a successful destroy, a new build creates an empty database with fresh synthetic test data. Use new globally unique resource names where retention prevents immediate name reuse.

### Destroy and verify complete removal

`Destroy-Lab.ps1` must:

1. Verify the explicit lab ID acknowledgement, subscription, manifest, and exact ownership scope. Display the deletion plan before mutation.
2. Disable scheduling, stop load generation, cancel active chaos actions, and reconcile outstanding faults.
3. Keep the cleanup manifest until verification completes. Export evidence only when explicitly requested; otherwise create no retained external copy. Abort before deleting evidence storage if a requested export fails.
4. Delete workload resources and track owned objects outside their groups, including DNS links, peerings, monitoring rules, deployment metadata, and runtime runners. Preserve the private cleanup path, controller, cleanup identities, and required role assignments until purge and verification finish.
5. Remove only explicitly tracked lab-owned locks. Reject unexpected resources in an allegedly dedicated group; never delete a shared hub or shared DNS zone.
6. Purge the deleted Key Vault and other customer-purgeable recoverable objects with supported APIs. Use permanent workspace deletion where supported. Remove lab-created directory objects when authorized.
7. After private cleanup finishes, finalize destruction from the operator machine or external CI control context. Remove lifecycle schedules, controller workers, account, control storage, remaining role/identity objects, and network dependencies in dependency order. Delete both lab-owned VNets, Bastion, NAT Gateway/public IPs, private endpoints, private DNS zones, peerings, and resource groups. Wait for asynchronous deletion and verify service-managed infrastructure cleanup.
8. Remove only the explicitly recorded temporary local state and downloaded lab data after customer-controlled cleanup. Preserve source code, input configuration, and unrelated files.
9. Report any remaining resources, retained service backups, audit records, deletion constraints, and expiry times. Support retry after interruption.

Customer-controlled cleanup requires removal of all owned active resources and every recoverable object for which Azure exposes an authorized purge operation. Keep Key Vault purge protection disabled at creation; mandatory soft delete is followed by explicit purge.

Azure Activity Log events cannot be changed or deleted and are retained for 90 days. PostgreSQL documents five-day retention of dropped-server backups. Record these platform constraints separately from removable lab resources.

Report `CustomerCleanupComplete` with a successful exit only when that scope is verified. Accepted mandatory Azure-managed remnants are informational and must be disclosed. Do not equate this outcome with universal erasure. Return nonzero for incomplete required cleanup, unauthorized purge, or undisclosed remnants.

### Suspend while preserving data

`Suspend-Lab.ps1` must first save active revisions, traffic weights, scaling/node settings, schedules, runtime states, and dependencies in an external state journal.

Then disable test and chaos schedules, quiesce application traffic, finish or explicitly fail in-flight writes, and export run evidence. Stop workloads before stopping their dependencies.

| Resource | Suspend behavior | Retained state or constraint |
| --- | --- | --- |
| Demo app and workload controller apps | Deactivate active revisions; disable scheduled jobs and stop running executions | Environment, networking, images, and configuration remain |
| Dedicated workload profile | Reduce the minimum to zero where supported and verify allocated nodes reach zero; otherwise use the lowest supported safe setting | List every retained node and its platform constraint |
| PostgreSQL HA | Use the supported server stop operation and verify the stopped state; preserve HA configuration and both roles' data | Data and backups remain; reconcile Azure's automatic start after seven days |
| Runner/load-generator VMs or scale sets | Deallocate compute after dependent work completes; disable autoscaling or schedules that could restart it | Preserve disks, configuration, and required addresses |
| Operations NAT Gateway and Bastion | Retain for private management, worker HTTPS access and resume | No data-preserving stop operation; delete during destroy |
| Unrelated subscription and tenant resources | Leave unchanged | Outside lab ownership; not required for the lab network |
| ACR, Key Vault, storage, private endpoints, DNS, and monitoring | Preserve configuration and data; suppress unnecessary probes and schedules without removing required security monitoring | Needed for private recovery and data preservation |
| DNS Private Resolver, Bastion, or gateways, if deployed | Retain services that lack a supported data-preserving stop operation | List every retained deployment and the reason |
| Lifecycle account, Hybrid Worker VMs, and control store | Remain available with their network dependencies to enforce desired state and support resume | Included in destroy scope and excluded from runtime suspension |

Do not treat `minReplicas = 0` alone as suspension: traffic or a scaler can reactivate the app. Verify that every active revision and restart trigger has been addressed.

Validate stop/start support for the exact PostgreSQL HA configuration during implementation. Never disable HA or weaken private access to make suspension succeed. Report unsupported operations and resources kept running for a dependency with the reason.

Keep the final orchestrator outside the resources it deallocates so it can verify completion. The operator machine or external CI control context must remain able to execute resume through authenticated Azure management APIs.

Return an inventory showing each resource's observed state, action taken, retained configuration, and next automatic-start deadline.

### Automatic 24-hour suspension

- Persist `readyAtUtc`, `suspendAtUtc = readyAtUtc + 24 hours`, and desired lifecycle state in the control store.
- Use a one-time Azure Automation schedule to invoke the same suspend workflow on the private Hybrid Worker group. The operator session and runtime VMs are not required to remain active.
- Azure Automation stores schedule start times at minute precision. Schedule the first full UTC minute at or after the exact persisted deadline, verify a delay of at least zero and less than 60 seconds, and preserve the exact deadline in state. Worker dispatch and resource transitions are measured separately. Scheduling before the deadline could cause the one-time reconciliation to return without suspending.
- Set a new deadline after successful resume. Traffic, tests, and idempotent build/resume reruns must not reset an existing deadline.
- At expiry, set desired state to suspended, inhibit new chaos events, cancel active campaigns, drain work with bounded timeouts, then acquire the lifecycle lock and suspend dependencies in order.
- Retain the Automation controller, its two private Hybrid Worker VMs, and minimal management permissions while suspended. These workers access private state and execute data-plane checks; ordinary build/load runners remain stopped. Keep required NAT, Azure DNS and private-zone links available.
- Reconcile suspended state hourly. If PostgreSQL becomes ready after automatic restart, safely stop it again. Never interpret that restart as authorization to resume the application.
- Detect missed schedules, failed state transitions, and permission errors. Alert, retry bounded operations, and report failure explicitly.
- Disable all lifecycle schedules during destruction and delete their controller last.

### Resume and restore the approved baseline

`Resume-Lab.ps1` must:

1. Load and validate the saved state, acquire the lifecycle lock, and record a bounded resuming transition so suspended-state reconciliation cannot stop a database being resumed. Detect concurrent changes and interrupted operations. On failure, return desired state to suspended and reconcile partial startup.
2. Verify retained NAT, DNS, private endpoints and direct peering first.
3. Start the bootstrap/private management runner when the initiating operator has only Azure management access. Verify private DNS, routes, NSGs, registry connectivity, and identity access from that private path. Preserve public-access denial throughout recovery.
4. Start PostgreSQL and wait for writable primary, healthy standby, distinct zones, and private connectivity. An already auto-started server must be reconciled safely.
5. Restore Dedicated profile capacity, the previous app revision/image digest, replica limits, and traffic configuration. Reconnect using refreshed identity tokens.
6. Start the remaining runner fleet and configured non-chaos schedules. Re-enable configured campaigns only when deterministic and preview validation gates pass.
7. Verify retained business data, successful reads/writes, baseline performance, monitoring, HA, and negative Internet-access checks. Arm a new 24-hour suspension deadline only after successful readiness.

Resume succeeds only after the approved HA baseline is restored. A running resource state alone is insufficient.

### Reliability and acceptance

- Use a lifecycle lock shared with the test controller so build, destroy, suspend, resume, and fault campaigns cannot overlap.
- Persist step-level state outside the suspended runtime, in the lab control store and temporary local directory. Retry only safe operations, surface partial failures, and return nonzero when required postconditions fail.
- Repeated suspend/resume/destroy commands must reconcile actual state without duplicating resources or resetting the saved baseline.
- Build success requires an operational private lab and verified automatic-suspension schedule. Suspend success requires verified stop/deallocation outcomes for all safely stoppable resources and an explicit retained-resource inventory.
- Test build-to-destroy and build-to-suspend-to-resume end to end. Also test interrupted operations, repeated calls, mismatched lab IDs, foreign resources, vault purge, service-managed retention, and PostgreSQL automatic-start reconciliation.
- AUTO-001 verifies the persisted deadline is exactly 24 hours after readiness and tests accelerated expiry, cancellation, retry, and controller independence in an isolated test configuration.
- AUTO-002 is a separate real 24-hour lifecycle soak test with the operator disconnected. Ordinary resilience sessions last a few hours. Verify workflow initiation within fifteen minutes of the scheduled deadline, observed suspended states, and no deadline extension from traffic or tests.

## 9. Implementation gates

1. Apply accepted HA, recovery, preview, region, address, identity, standalone-network, and deletion decisions. Supply deployment inputs.
2. Confirm regional service/SKU capacity, Bicep API versions, current Chaos action schemas, private telemetry delivery, the replica-control prototype, and service-specific suspend/resume support.
3. Build and validate Bicep. Review deployment what-if, policy results, and security findings before provisioning.
4. Verify private deployment, image pulls, migrations, authentication, token renewal, telemetry, backups, and public-access denial.
5. Pass application tests, idempotency and fault-guard tests, both lifecycle sequences, automatic-suspension tests, preview validations, BASE-001, and the deterministic component tests.
6. Enable approved random campaigns. Require qualifying full-zone evidence before asserting a pass for HA-AZ-001.

Destroy requires explicit lab-ID acknowledgement. Export evidence only on request, remove customer-controlled resources and temporary data, and report mandatory Azure-managed retention honestly.

## 10. Boundaries

### Public source and private execution context

Keep account, tenant/subscription IDs, real group names, authentication-profile paths, governance identifiers and raw execution evidence outside publishable sources. Use ignored `.local/environment.json` for the exact authorized context, with the empty `config/environment.example.json` as the public setup template. Keep the environment-specific deployment plan and validation state in ignored `.azure/`.

Scripts and templates receive the context as configuration/parameters and retain exact identity, ownership and deletion checks. Public documentation uses generic references and sanitized summaries. Run `tests/Test-Publication.ps1` before creating/pushing the future repository. Git ignore rules do not protect full-folder archives or erase data already committed to history.

The first iteration covers one region, one-zone-loss resilience, and bounded non-production chaos campaigns. Regional disaster recovery, multi-zone simultaneous failure, destructive data tests, and continuous production chaos require separate approval and specifications.

For the platform facts behind these decisions, see [Research and technical constraints](research.md).
