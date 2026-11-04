$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Common helper parsing failed.' }
foreach ($name in @('Assert-LabAppServicePlan', 'Assert-LabAppServicePlacement')) {
    $definitions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    }, $true))
    . ([scriptblock]::Create($definitions[0].Extent.Text))
}
function Expect-Blocked([scriptblock] $Action) {
    $blocked = $false
    try { & $Action } catch { $blocked = $_.Exception.Message -like 'BLOCKED:*' }
    if (-not $blocked) { throw 'A required exact placement/capability gate was bypassed.' }
}
$plan = @{kind='linux'; properties=@{reserved=$true;zoneRedundant=$true;perSiteScaling=$false;maximumNumberOfZones=3};sku=@{capacity=6}}
$instances = @(0..5 | ForEach-Object { @{name="instance-$_";properties=@{physicalZone="region-az$([int][Math]::Floor($_/2)+1)"}} })
$observations = @($instances | ForEach-Object { @{instanceId=$_.name;status='live';businessSuccess=$true} })
Assert-LabAppServicePlacement $plan $instances $observations
$plan.properties.maximumNumberOfZones = 2
Expect-Blocked { Assert-LabAppServicePlacement $plan $instances $observations }
$plan.properties.Remove('maximumNumberOfZones')
Expect-Blocked { Assert-LabAppServicePlan $plan }
$plan.properties.maximumNumberOfZones = 3
$plan.properties.reserved = $false
Expect-Blocked { Assert-LabAppServicePlan $plan }
$plan.properties.reserved = $true
$plan.properties.perSiteScaling = $true
Expect-Blocked { Assert-LabAppServicePlan $plan }
$plan.properties.perSiteScaling = $false
$plan.sku.capacity = 5
Expect-Blocked { Assert-LabAppServicePlan $plan }
$plan.sku.capacity = 6
Expect-Blocked { Assert-LabAppServicePlacement $plan $instances[0..4] $observations }
Expect-Blocked { Assert-LabAppServicePlacement $plan $instances $observations[0..4] }
$instances[5].properties.physicalZone = ''
Expect-Blocked { Assert-LabAppServicePlacement $plan $instances $observations }
$instances[5].properties.physicalZone = 'region-az3'
$instances[4].properties.physicalZone = 'region-az2'
$instances[5].properties.physicalZone = 'region-az2'
Expect-Blocked { Assert-LabAppServicePlacement $plan $instances $observations }
'Actual plan, exact six-instance inventory, all-instance health/traffic and three distinct physical-zone gates passed.'
