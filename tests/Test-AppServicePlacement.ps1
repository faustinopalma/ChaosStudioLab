$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Common helper parsing failed.' }
foreach ($name in @('Assert-LabAppServicePlan', 'Assert-LabAppServiceConfiguration', 'Assert-LabAppServicePlacement', 'Get-LabApplicationTarget')) {
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
Assert-LabAppServiceConfiguration @{alwaysOn=$true;linuxFxVersion='DOTNETCORE|9.0'}
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn=$false} }
Expect-Blocked { Assert-LabAppServiceConfiguration @{} }
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn='true'} }
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn=$true} }
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn=$true;linuxFxVersion='DOTNETCORE|10.0'} }
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
$instances[4].properties.physicalZone = 'region-az3'
$instances[5].properties.physicalZone = 'region-az3'
$windowsPlan = @{kind='app'; properties=@{reserved=$false;zoneRedundant=$true;perSiteScaling=$false;maximumNumberOfZones=3};sku=@{capacity=6}}
Assert-LabAppServicePlan $windowsPlan windows
Assert-LabAppServicePlacement $windowsPlan $instances $observations windows
Expect-Blocked { Assert-LabAppServicePlan $windowsPlan }
Expect-Blocked { Assert-LabAppServicePlan $plan windows }
$windowsPlan.properties.zoneRedundant = $false
Expect-Blocked { Assert-LabAppServicePlan $windowsPlan windows }
$windowsConfiguration = @{alwaysOn=$true;netFrameworkVersion='v9.0';use32BitWorkerProcess=$false;linuxFxVersion=''}
Assert-LabAppServiceConfiguration $windowsConfiguration windows
Expect-Blocked { Assert-LabAppServiceConfiguration $windowsConfiguration }
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn=$true;netFrameworkVersion='v9.0';use32BitWorkerProcess=$true} windows }
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn=$true;netFrameworkVersion='v8.0';use32BitWorkerProcess=$false} windows }
Expect-Blocked { Assert-LabAppServiceConfiguration @{alwaysOn=$true;linuxFxVersion='DOTNETCORE|9.0'} windows }
$linuxId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Web/sites/csl-api-x'
$windowsId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.Web/sites/csl-win-x'
$workload = (@{applicationId=$linuxId;applicationName='csl-api-x';applicationFqdn='a';scmFqdn='b';postgresName='pg';migrationClientId='m'} | ConvertTo-Json | ConvertFrom-Json -AsHashtable)
$manifest = @{outputs=@{'csl-infrastructure'=@{workload=@{value=$workload}}}}
$target = Get-LabApplicationTarget $manifest
if ($target.platform -ne 'linux' -or $target.planId -notlike '*/serverfarms/asp-csl-linux-baseline' -or $target.migrationClientId -ne 'm' -or
    $target.nativeScenariosOutput -ne 'csl-native-process-scenarios' -or $target.nativeSelectionKey -ne 'nativeSelection') {
    throw 'Default Linux application target drifted.'
}
$manifest.applicationTarget = 'windows'
$blocked = $false
try { Get-LabApplicationTarget $manifest | Out-Null } catch { $blocked = $_.Exception.Message -like 'BLOCKED:*' }
if (-not $blocked) { throw 'Undeployed Windows target was accepted.' }
$manifest.outputs['csl-windows-application'] = @{applicationId=@{value=$windowsId};applicationName=@{value='csl-win-x'};applicationFqdn=@{value='w'};scmFqdn=@{value='ws'}}
$target = Get-LabApplicationTarget $manifest
if ($target.platform -ne 'windows' -or $target.applicationId -ne $windowsId -or $target.scmFqdn -ne 'ws' -or
    $target.postgresName -ne 'pg' -or $target.planId -notlike '*/serverfarms/asp-csl-windows-baseline' -or
    $target.nativeScenariosOutput -ne 'csl-native-process-scenarios-windows' -or
    $manifest.outputs['csl-infrastructure'].workload.value.applicationId -ne $linuxId) {
    throw 'Windows application target selection drifted or mutated shared Linux outputs.'
}
$manifest.applicationTarget = 'other'
try { Get-LabApplicationTarget $manifest | Out-Null; throw 'Unsupported target accepted.' } catch { if ($_.Exception.Message -eq 'Unsupported target accepted.') { throw } }
'Actual Linux/Windows plan, exact six-instance inventory, all-instance health/traffic and three distinct physical-zone gates passed.'
