# Running the lab

[Executive summary](executive-summary.md) | [Method](method.md)

The scripts deploy private Azure resources that cost money while they run: PostgreSQL with zone-redundant HA, Azure Managed Redis, a Premium registry, Bastion, two NAT gateways and the compute platform under test. A complete platform run takes about four to six hours, including roughly 30 minutes of provisioning. Delete the owned resource groups when the measurements end.

## Prerequisites

You need an Azure subscription where you can create resource groups and role assignments, Azure CLI with Bicep, PowerShell 7, the .NET 10 SDK for the unit tests, and the Bastion CLI extension for the SSH tunnel. The runner VM installs k6, Docker and the remaining tools itself.

Private settings live in an ignored file under `.local\`, selected with the `CSL_ENVIRONMENT_FILE` environment variable. Start from [config/environment.example.json](../config/environment.example.json) and fill in the subscription, tenant, approved account, Azure CLI configuration directory, region and fresh resource-group names. The AKS lab also needs `aksNodeResourceGroup`, and the Container Apps lab needs `acaInfrastructureResourceGroup`. If your subscription policy blocks public IPs, list the required exemption in `requiredPolicyExemptions`; the scope stage creates it on the network group only.

Each build stage reads `.azure\deployment-plan.md` and refuses to run unless the plan is marked `Validated` and lists the stage. Every stage then validates and previews its template, rejects changes outside the owned groups, deploys, and records the resulting inventory in the manifest.

## Container Apps

```powershell
$env:CSL_ENVIRONMENT_FILE = '.local\environment-aca.json'
.\scripts\Test-AcaPreflight.ps1 -StateDirectory .local\aca-run
foreach ($step in 'Scope','Identities','Infrastructure','EnvironmentDns','Access','Runner') {
    .\scripts\Build-AcaLab.ps1 -ManifestPath .local\aca-run\manifest.json -Step $step
}
# In a separate shell, keep the tunnel open:
# az network bastion tunnel --name bas-csl-operations --resource-group <operations group> --target-resource-id <runner VM id> --resource-port 22 --port 40222
.\scripts\Build-AcaLab.ps1 -ManifestPath .local\aca-run\manifest.json -Step Application
.\scripts\Build-AcaLab.ps1 -ManifestPath .local\aca-run\manifest.json -Step Native
foreach ($test in 'BASE-001','HA-REPLICA-001','HA-DB-001','HA-COMBINED-001') {
    .\scripts\Test-AcaLab.ps1 -ManifestPath .local\aca-run\manifest.json -TestId $test
}
```

The preflight records every resource outside the lab so the final inventory can be compared with it. `Application` migrates the database, builds the image on the runner, pushes it to the private registry, deploys the container app with that exact digest and runs the private smoke and durability checks. Each test writes its measurements and evidence under `.local\aca-run\tests\`.

## AKS and App Service

The AKS lab follows the same pattern with `Test-AksPreflight.ps1`, `Build-AksLab.ps1` (stages `Scope`, `Identities`, `Infrastructure`, `Access`, `Runner`, `ReadCache`, `Application`, `Native`) and `Test-AksLab.ps1` (tests `BASE-001`, `HA-NODE-001`, `HA-ZONE-COMPUTE-001`, `HA-DB-001`, `HA-COMBINED-001`). The App Service lab uses `Test-AppServicePreflight.ps1`, `Build-Lab.ps1` (stages `Plan`, `Prerequisites`, `Infrastructure`, `Runner`, `Application`, `NativeScenarios`) and `Test-Lab.ps1` (tests `BASE-001`, `HA-APP-001`, `HA-APP-ZONE-001`, `HA-DB-001`, `HA-COMBINED-001`).

## Local checks

```powershell
dotnet test src\Demo.Api.Tests\Demo.Api.Tests.csproj -p:LabTargetFramework=net10.0
Get-ChildItem tests\load\Test-*.ps1, tests\Test-*.ps1 | ForEach-Object { & $_.FullName }
pwsh .\tests\Test-Publication.ps1
```

The first command runs the API unit tests. The second runs the evaluator, contract and guard fixtures without Azure access; `Test-K6Format.ps1` also needs k6 on `PATH`, and `Test-AppServiceIdentity.ps1` needs the .NET 9 runtime. The publication guard should pass before every commit.

## Cleanup

Delete the workload group first; Container Apps and AKS then remove their managed infrastructure group. Delete the operations and network groups afterwards, and compare the subscription inventory with the preflight snapshot. Key Vault keeps a soft-deleted copy for seven days, and PostgreSQL backups and the Activity Log follow their own retention.
