[CmdletBinding()]
param([Parameter(Mandatory)][string] $StateDirectory)
. (Join-Path $PSScriptRoot 'Lab.Aks.ps1')
Confirm-LabContext
$root = [IO.Path]::GetFullPath($StateDirectory)
if (-not $root.StartsWith((Join-Path $script:LabRoot '.local') + '\', [StringComparison]::OrdinalIgnoreCase) -or
    (Test-Path (Join-Path $root 'manifest.json'))) { throw 'Use fresh ignored state; manifests are never overwritten.' }
New-Item -ItemType Directory -Path $root -Force | Out-Null
$groups = Invoke-LabAz @('group', 'list', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json -AsHashtable
if (@($groups | Where-Object name -In $script:LabGroups).Count) { throw 'A proposed group already exists; never adopt it.' }
Write-LabJson "$root\groups-before.json" $groups
$resources = Invoke-LabAz @('resource', 'list', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json -AsHashtable
Write-LabJson "$root\protected-resources-before.json" @($resources)
$id = [Guid]::NewGuid().ToString('N')
$m = @{
    schemaVersion = 1; architecture = 'private-aks'; labId = 'lab-dev01'
    subscriptionId = $script:LabSubscription; tenantId = $script:LabTenant
    deploymentInstanceId = $id; createdAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    groups = @($script:LabGroups | ForEach-Object { @{name = $_; id = "/subscriptions/$script:LabSubscription/resourceGroups/$_"} })
    resourceIds = @(); outputs = @{}; status = 'PREFLIGHT_ONLY'
    policyExemptions = @($script:LabEnvironment.requiredPolicyExemptions)
    activeNativeOperations = @()
}
Write-LabJson "$root\manifest.json" $m
Write-Output 'Fresh owned AKS scope and protected-project baseline persisted. No resources created.'
