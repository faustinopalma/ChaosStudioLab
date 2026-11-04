# Azure Chaos Studio resilience lab

This project defines a resilience lab for an enterprise-style application built on Azure Container Apps and Azure Database for PostgreSQL Flexible Server.

The target architecture uses a three-availability-zone Azure region, zone-redundant services, VNet integration, private endpoints, and controlled egress.

The focused [D14 topology](DECISIONS-ACCEPTED.md#d14-focused-chaosha-laboratory-networking) uses two directly peered VNets, private DNS, and operations NAT/Bastion, without Azure Firewall or a hub VNet. Required NAT/Bastion public IPs use Azure-allocated Standard static IPv4 under D13; BYOIP and `AllowBringYourOwnPublicIpAddress` remain excluded. The temporary [D15 exemption](DECISIONS-ACCEPTED.md#d15-temporary-lab-only-public-ip-policy-exemption) resolved the declared-public-IP blocker. The [Sweden Central execution](docs/first-cycle-results.md#latest-verified-results) provisioned the complete private HA stack and passed private API integration, full warmup/baseline and genuine PostgreSQL failover recovery in **38.624 seconds**. The report records lifecycle, durability, cleanup and remaining acceptance limits separately.

## Documents

- [Architecture and operating guide](docs/architecture-guide.md): illustrated walkthrough of the private request path, HA experiments, evidence, and lab lifecycle using all three diagrams.
- [Development readiness assessment](docs/development-readiness.md): what is sufficient to start, technical contracts to define, platform checks, and conditions requiring a new decision.
- [Implementation contracts](docs/implementation-contracts.md): the current API, persistence, measurement, deployment, and verification contracts.
- [Autonomous lab cycle method](docs/lab-cycle-method.md): exact ownership boundaries, private bootstrap, real-test protocol, lifecycle control, cleanup, and repeatable commands.
- [First Azure execution results](docs/first-cycle-results.md): measured workload/recovery, troubleshooting chronology, lifecycle/cleanup evidence and retained provider resources.
- [Implementation specification](docs/specification.md): requirements, architecture, application behavior, tests, lifecycle commands, and repository structure.
- [Research and technical constraints](docs/research.md): verified Azure capabilities, test limitations, networking choices, and Microsoft documentation.
- [Architecture and flow diagrams](docs/diagrams/README.md): editable Inkscape SVGs and PNG previews for the private architecture, HA tests, and lab lifecycle.

## Lab lifecycle

The specification defines four lifecycle entry points:

- **Build:** provision and verify the complete private lab from one command.
- **Destroy:** delete lab-owned resources and data, purge supported recoverable objects, and report mandatory service-retention limits.
- **Suspend:** stop or deallocate supported resources while preserving data and configuration.
- **Resume:** restore the saved configuration and verify the HA baseline.

Automatic suspension starts 24 hours after build or resume. The lifecycle controller reconciles suspended state, including PostgreSQL's automatic restart after seven days.

## Local API and load-test checks

The initial .NET API and its unit tests are under `src\Demo.Api\` and `src\Demo.Api.Tests\`. Run the local test suite with:

```powershell
dotnet test .\src\Demo.Api.Tests\Demo.Api.Tests.csproj --configuration Release
```

The private-runner k6 workload is `tests\load\scenario.js`, invoked by `tests\load\run.ps1`. It schedules the configured 20 operations per second at an 80/20 read/write ratio and a separate one-second canary. Writes reuse their operation ID across retries and are reconciled by checksum. Set `API_BASE_URL` and `API_TOKEN` in the runner process environment before invoking the script; the token is not stored in the repository or run artifacts. The target must use HTTPS and be reachable from the private runner. The default phase gate requires at least 99.9% successful business operations and p95 no greater than one second; override thresholds only to match the applicable approved test.

Run outputs are written under `.local\runs\<run-id>\` as raw attempt events, k6 metrics, a k6 summary, and run metadata. A `PASS` in `run.json` means that the configured k6 thresholds passed for that phase. HA recovery has a separate evidence-based verdict. The actual k6 1.5.0 output format and private cloud workload have been exercised. The injected phase's full-period availability and its post-injection recovery verdict are reported separately.

For a supported database-failover run, `tests\load\evaluate-recovery.ps1` calculates the first complete recovery window from the raw events. It requires the private run's `attempts.ndjson` and an independent `schemaVersion: 1` failover evidence JSON containing `source`, `targetResourceId`, `actionSucceeded`, `observedAtUtc`, and `noInterruption`. The default evaluator expects 20 workload operations per second plus exactly one canary tick per second; its `-ExpectedOperationsPerSecond` parameter must match the run's configured rate. It reports `INCONCLUSIVE` when evidence or samples are incomplete and will not accept zero recovery time without `noInterruption: true`.

Run the local synthetic load-runner and recovery-verdict tests without Azure or k6:

```powershell
pwsh .\tests\load\Test-LoadRunner.ps1
pwsh .\tests\load\Test-RecoveryEvaluator.ps1
```

## Repeat the Azure cycle

### Private environment configuration and publication

Copy `config\environment.example.json` to `.local\environment.json` and fill in the approved subscription, tenant, exact account, Azure CLI profile directory and three new dedicated resource-group names. Deployment defaults select Sweden Central; adapters support Sweden Central and North Europe. Infrastructure startup requires the exact subscription/region's top-level PostgreSQL `restricted: Disabled` and `zoneRedundantHaSupported: Enabled`; SKU-level HA metadata alone is insufficient. Other regions require DNS/service-tag/API validation. `config\lab.json` contains publishable design defaults, without account identifiers.

All operator scripts load the ignored local environment file. Set `CSL_ENVIRONMENT_FILE` to select another private file; keep it outside publication candidates. Account, subscription and tenant mismatches fail before mutation. Group ownership and manifest checks still constrain all writes and deletion. The template's group names are required parameters, populated from the same local context. Lifecycle jobs receive that exact scope as parameters.

Record required policy exemptions in the local file's `requiredPolicyExemptions` array (`id`, `assignmentId`, singleton `referenceIds`). Build/cycle/Resume check the live exemption before mutations and block missing/expired or changed records; near expiry produces a warning. The error identifies the group/exemption and directs an approved create-or-extend action in **Policy > Exemptions**. Renewal is manual and must be revalidated. Keep this local contract after cleanup so future starts still detect the missing waiver. See the [expiry recovery procedure](docs/lab-cycle-method.md#expired-or-missing-exemptions-on-a-later-start).

Keep manifests, raw logs, resource IDs, policy details, SSH keys, validation proof and the deployment plan in the ignored `.local\` and `.azure\` directories. Public reports summarize method and measured results without tenant/operator identifiers. Share the source through Git rather than a full-folder archive, which would include ignored private files.

Before publication, run:

```powershell
pwsh .\tests\Test-Publication.ps1
```

The check uses Git's actual ignore rules without initializing this workspace. It checks private-path exclusions, known local identifiers, tenant/resource paths and private-key markers across publication candidates. In an existing repository it also rejects tracked ignored files. Review any new identifiers or artifacts manually; this check does not certify arbitrary files as secret-free. If private files were previously committed, ignoring them does not remove earlier Git history; clean that history and rotate any exposed credentials before publication.

After preparing the private context, any required finite exemption and a validated deployment plan:

```powershell
pwsh .\scripts\Invoke-LabCycle.ps1 -IncludeLifecycleSmoke
```

The script checks policy-adjusted public-IP payloads before resource deployment, runs the private build/test stages, and invokes exact-manifest cleanup on success or failure. `-IncludeLifecycleSmoke` adds actual Reconcile/Suspend/Resume and retained-write verification; omit it for the shorter sequence. It never requires or registers the BYOIP feature. Changes outside the dedicated groups are reported for attribution and prevent a full cleanup verdict.

For staged troubleshooting, validate the prerequisite phase and run `Build-Lab.ps1 -Step Prerequisites` with the same owned manifest. This creates only the five managed identities from their exact compiled source declarations. ARM what-if can leave `reference()`-based principal IDs unresolved even after creation, so the build/validation resolve live, inventoried, correctly owned identities and supply `prerequisitePrincipalIds` explicitly. Repeat full-stack validation before `-Step Infrastructure`; a plan with `Validated build steps` limits execution to the explicitly validated steps. Keep successful owned resources while retrying a failed stage, and destroy the exact manifest when finished. Preview/provisioning/deletion timestamps distinguish provider waits from load-test time.

For an in-progress preparation whose owned network group still exists, select its private context and continue after full validation with its original manifest (replace the example paths with that run's actual paths):

```powershell
$env:CSL_ENVIRONMENT_FILE = Join-Path $PWD '.local\environment.json'
pwsh .\scripts\Invoke-LabCycle.ps1 -ManifestPath .\.local\prepared-run\manifest.json
```

Read the current run's finite waiver expiry from live Azure and its ignored manifest; deleting the owned group also removes the waiver. Recheck live existence, scope, expiry and effective payload before provisioning. A default fresh manifest refuses to adopt an existing group, and destroyed manifests must be replaced for a new run. The original policy-exception run is destroyed; its manifest is historical evidence. Exact identifiers and evidence stay ignored; the [execution report](docs/first-cycle-results.md#regional-retry-and-timing-diagnosis) records sanitized timings and retries. Keep the environment exemption contract after cleanup so later starts explicitly remind the operator to prepare a new approved waiver.
