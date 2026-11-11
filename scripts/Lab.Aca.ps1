. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
if (-not $script:LabEnvironment.ContainsKey('acaInfrastructureResourceGroup') -or
    $script:LabEnvironment.acaInfrastructureResourceGroup -notmatch '^rg-csl-aca-infra-[a-z0-9-]+$') {
    throw 'An explicit fresh Container Apps infrastructure group is required in the private environment.'
}
$script:LabGroups += $script:LabEnvironment.acaInfrastructureResourceGroup
$script:AcaBaseInventory = ${function:Get-LabInventory}
$script:AcaBaseDeployment = ${function:Invoke-LabDeployment}

function Invoke-LabDeployment {
    param([hashtable] $Manifest, [string] $ManifestPath, [string] $Group, [string] $Name, [string] $Template, [hashtable] $Parameters)
    $root = Split-Path $ManifestPath -Parent
    $path = Join-Path $root "$Name.validation-parameters.json"
    $values = @{}
    foreach ($entry in $Parameters.GetEnumerator()) { $values[$entry.Key] = @{value=$entry.Value} }
    Write-LabJson $path @{parameters=$values}
    try {
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] ARM validating exact ACA stage $Name." -InformationAction Continue
        $validation = Invoke-LabAz @('deployment','group','validate','-g',$Group,'--template-file',$Template,'--parameters',"@$path",'-o','json') | ConvertFrom-Json -AsHashtable
        Write-LabJson (Join-Path $root "$Name.arm-validation.json") $validation
        if ($validation.properties.provisioningState -ne 'Succeeded') { throw "ARM validation failed for $Name." }
        return & $script:AcaBaseDeployment $Manifest $ManifestPath $Group $Name $Template $Parameters
    } finally { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
}

function Get-LabInventory {
    param([hashtable] $Manifest)
    if ($Manifest.ContainsKey('managedInfrastructureGroupVerified') -and $Manifest.managedInfrastructureGroupVerified) {
        return & $script:AcaBaseInventory $Manifest
    }
    $initial = $Manifest.Clone()
    $initial.groups = @($Manifest.groups[0..2])
    return & $script:AcaBaseInventory $initial
}

function Read-LabManifest {
    param([string] $Path)
    $m = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($m.schemaVersion -ne 1 -or $m.architecture -ne 'private-aca' -or
        $m.subscriptionId -ne $script:LabSubscription -or $m.tenantId -ne $script:LabTenant -or
        $m.labId -ne 'lab-dev01' -or $m.deploymentInstanceId -notmatch '^[0-9a-f]{32}$' -or
        @($m.groups).Count -ne 4 -or @($script:LabGroups | Where-Object { $_ -notin $m.groups.name }).Count) {
        throw 'Invalid or foreign private Container Apps manifest.'
    }
    foreach ($group in $m.groups) {
        if ($group.id -ine "/subscriptions/$script:LabSubscription/resourceGroups/$($group.name)") { throw 'Container Apps group ID mismatch.' }
    }
    foreach ($id in $m.resourceIds) { Assert-LabResourceId $id }
    return $m
}

function Invoke-AcaPrivate {
    param([hashtable] $Manifest, [string] $StateRoot, [string] $Command, [int] $TunnelPort)
    $options = @(Get-LabSshOptions $Manifest $StateRoot)
    & ssh @options -p $TunnelPort csloperator@127.0.0.1 $Command
    if ($LASTEXITCODE -ne 0) { throw "Private runner command failed ($LASTEXITCODE)." }
}

function Assert-AcaProtectedInventory {
    param([string] $StateRoot)
    $before = @(Get-Content (Join-Path $StateRoot 'protected-resources-before.json') -Raw | ConvertFrom-Json -AsHashtable)
    $after = Invoke-LabAz @('resource', 'list', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json -AsHashtable
    $other = @($after | Where-Object resourceGroup -NotIn $script:LabGroups)
    Write-LabJson (Join-Path $StateRoot 'protected-resources-after.json') $other
    $delta = @(Compare-Object @($before.id | Sort-Object) @($other.id | Sort-Object))
    return @{ unchanged = $delta.Count -eq 0; beforeCount = $before.Count; afterCount = $other.Count; delta = @($delta | ForEach-Object { @{ id = $_.InputObject; side = $_.SideIndicator } }) }
}
