. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
if (-not $script:LabEnvironment.ContainsKey('aksNodeResourceGroup') -or
    $script:LabEnvironment.aksNodeResourceGroup -notmatch '^rg-csl-aks-nodes-[a-z0-9-]+$') {
    throw 'An explicit fresh AKS managed node group is required in the private environment.'
}
$script:LabGroups += $script:LabEnvironment.aksNodeResourceGroup
$script:AksBaseInventory = ${function:Get-LabInventory}
$script:AksBaseDeployment = ${function:Invoke-LabDeployment}

function Invoke-LabDeployment {
    param([hashtable] $Manifest, [string] $ManifestPath, [string] $Group, [string] $Name, [string] $Template, [hashtable] $Parameters)
    $root = Split-Path $ManifestPath -Parent
    $path = Join-Path $root "$Name.validation-parameters.json"
    $values = @{}
    foreach ($entry in $Parameters.GetEnumerator()) { $values[$entry.Key] = @{value=$entry.Value} }
    Write-LabJson $path @{parameters=$values}
    try {
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] ARM validating exact AKS stage $Name." -InformationAction Continue
        $validation = Invoke-LabAz @('deployment','group','validate','-g',$Group,'--template-file',$Template,'--parameters',"@$path",'-o','json') | ConvertFrom-Json -AsHashtable
        Write-LabJson (Join-Path $root "$Name.arm-validation.json") $validation
        if ($validation.properties.provisioningState -ne 'Succeeded') { throw "ARM validation failed for $Name." }
        return & $script:AksBaseDeployment $Manifest $ManifestPath $Group $Name $Template $Parameters
    } finally { Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue }
}

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
    $before = @(Get-Content (Join-Path $StateRoot 'protected-resources-before.json') -Raw | ConvertFrom-Json -AsHashtable)
    $after = Invoke-LabAz @('resource', 'list', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json -AsHashtable
    $other = @($after | Where-Object resourceGroup -NotIn $script:LabGroups)
    Write-LabJson (Join-Path $StateRoot 'protected-resources-after.json') $other
    if (@(Compare-Object @($before.id | Sort-Object) @($other.id | Sort-Object)).Count) {
        throw 'Other-project resource inventory changed; inspect before/after snapshots.'
    }
    foreach ($resource in $before) {
        $current = @($other | Where-Object id -EQ $resource.id)[0]
        $expectedJson = [Newtonsoft.Json.Linq.JToken]::Parse(($resource | ConvertTo-Json -Depth 100 -Compress))
        $currentJson = [Newtonsoft.Json.Linq.JToken]::Parse(($current | ConvertTo-Json -Depth 100 -Compress))
        if (-not [Newtonsoft.Json.Linq.JToken]::DeepEquals($expectedJson, $currentJson)) {
            throw 'Other-project resource metadata changed; inspect the preserved before/after snapshots.'
        }
    }
}
