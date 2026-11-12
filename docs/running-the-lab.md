# Running the lab

[Executive summary](executive-summary.md) | [Method](method.md)

The scripts deploy private Azure resources that cost money while they run: PostgreSQL with zone-redundant HA, Azure Managed Redis, a Premium registry, Bastion, NAT gateways and the platform under test. One platform takes about four hours: about 75 minutes of build stages, including 25 minutes of provisioning, and about two hours of measurements. Delete the lab resource groups afterwards.

## Prerequisites

You need an Azure subscription where you can create resource groups and role assignments, Azure CLI with Bicep and the Bastion extension, PowerShell 7, and the .NET 10 SDK for the unit tests. The runner VM installs k6, Docker and its other tools itself.

Private settings live in an ignored JSON file under `.local\`, selected with the `CSL_ENVIRONMENT_FILE` environment variable. Start from [config/environment.example.json](../config/environment.example.json) and fill in the subscription, tenant, approved account, Azure CLI configuration directory, region and fresh resource-group names; Container Apps also needs `acaInfrastructureResourceGroup` and AKS needs `aksNodeResourceGroup`. If a subscription policy requires an exemption for the NAT and Bastion public IPs, list it in `requiredPolicyExemptions`.

Each build stage also checks an ignored `.azure\deployment-plan.md`, where you record the approved plan. It must contain `**Status:** Validated` and a line `**Validated build steps:**` followed by the comma-separated stage names. Every stage then validates and previews its template, rejects changes outside the lab groups, deploys, and records the resulting inventory in the manifest.

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

The preflight records every resource outside the lab so the final inventory can be compared with it. `Application` migrates the database, builds the image on the runner, pushes it to the private registry, deploys the container app with that exact digest and runs private smoke and durability checks. Each test writes its measurements and evidence under `.local\aca-run\tests\`.

## AKS and App Service

AKS follows the same pattern with `Test-AksPreflight.ps1`, `Build-AksLab.ps1` (stages `Scope`, `Identities`, `Infrastructure`, `Access`, `Runner`, `ReadCache`, `Application`, `Native`) and `Test-AksLab.ps1` (tests `BASE-001`, `HA-NODE-001`, `HA-ZONE-COMPUTE-001`, `HA-DB-001`, `HA-COMBINED-001`). App Service uses `Test-AppServicePreflight.ps1`, `Build-Lab.ps1` (stages `Plan`, `Prerequisites`, `Infrastructure`, `Runner`, `Application`, `NativeScenarios`) and `Test-Lab.ps1` (tests `BASE-001`, `HA-APP-001`, `HA-APP-ZONE-001`, `HA-DB-001`, `HA-COMBINED-001`).

## Local checks

```powershell
dotnet test src\Demo.Api.Tests\Demo.Api.Tests.csproj -p:LabTargetFramework=net10.0
Get-ChildItem tests\load\Test-*.ps1, tests\Test-*.ps1 | ForEach-Object { & $_.FullName }
pwsh .\tests\Test-Publication.ps1
```

The first command runs the API unit tests, the second the evaluator, contract and guard fixtures without Azure access (`Test-K6Format.ps1` also needs k6, and `Test-AppServiceIdentity.ps1` the .NET 9 runtime), and the third the publication guard.

## Cleanup

Delete the workload group first; Container Apps and AKS then remove their managed infrastructure group. Delete the operations and network groups afterwards and compare the subscription inventory with the preflight snapshot. Key Vault keeps a soft-deleted copy for seven days unless purged.
