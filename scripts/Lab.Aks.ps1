. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
if (-not $script:LabEnvironment.ContainsKey('aksNodeResourceGroup') -or
    $script:LabEnvironment.aksNodeResourceGroup -notmatch '^rg-csl-aks-nodes-[a-z0-9-]+$') {
    throw 'An explicit fresh AKS managed node group is required in the private environment.'
}
$script:LabGroups += $script:LabEnvironment.aksNodeResourceGroup
$script:AksBaseInventory = ${function:Get-LabInventory}

function Get-LabInventory {
    param([hashtable] $Manifest)
    if ($Manifest.ContainsKey('managedNodeGroupVerified') -and $Manifest.managedNodeGroupVerified) {
        return & $script:AksBaseInventory $Manifest
    }
    $initial = $Manifest.Clone()
    $initial.groups = @($Manifest.groups[0..2])
    return & $script:AksBaseInventory $initial
}

function Read-LabManifest {
    param([string] $Path)
    $m = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($m.schemaVersion -ne 1 -or $m.architecture -ne 'private-aks' -or
        $m.subscriptionId -ne $script:LabSubscription -or $m.tenantId -ne $script:LabTenant -or
        $m.labId -ne 'lab-dev01' -or $m.deploymentInstanceId -notmatch '^[0-9a-f]{32}$' -or
        @($m.groups).Count -ne 4 -or @($script:LabGroups | Where-Object { $_ -notin $m.groups.name }).Count) {
        throw 'Invalid or foreign private AKS manifest.'
    }
    foreach ($group in $m.groups) {
        if ($group.id -ine "/subscriptions/$script:LabSubscription/resourceGroups/$($group.name)") {
            throw 'AKS group ID mismatch.'
        }
    }
    foreach ($id in $m.resourceIds) { Assert-LabResourceId $id }
    return $m
}

function Invoke-AksPrivate {
    param([hashtable] $Manifest, [string] $StateRoot, [string] $Command, [int] $TunnelPort = 50222)
    $options = @(Get-LabSshOptions $Manifest $StateRoot)
    & ssh @options -p $TunnelPort csloperator@127.0.0.1 $Command
    if ($LASTEXITCODE -ne 0) { throw "Private runner command failed ($LASTEXITCODE)." }
}

function Assert-AksProtectedInventory {
    param([string] $StateRoot)
    $before = Get-Content (Join-Path $StateRoot 'protected-resources-before.json') -Raw | ConvertFrom-Json -AsHashtable
    $after = Invoke-LabAz @('resource', 'list', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json -AsHashtable
    $other = @($after | Where-Object resourceGroup -NotIn $script:LabGroups)
    if (@(Compare-Object @($before.id | Sort-Object) @($other.id | Sort-Object)).Count) {
        throw 'Other-project resource inventory changed; inspect before/after snapshots.'
    }
    Write-LabJson (Join-Path $StateRoot 'protected-resources-after.json') $other
}
