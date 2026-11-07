$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. "$PSScriptRoot\..\scripts\Lab.Aks.Native.ps1"
$subscription='00000000-0000-0000-0000-000000000001'
$prefix="/subscriptions/$subscription/resourceGroups/rg-owned"
function Assert-LabResourceId([string] $Id){
    if(-not $Id.StartsWith("$prefix/",[StringComparison]::OrdinalIgnoreCase)){throw 'Foreign test resource.'}
}
$target="$prefix/providers/Microsoft.Compute/virtualMachineScaleSets/one"
$scenarioId="$prefix/providers/Microsoft.Chaos/workspaces/ws/scenarios/one"
$scenario=@{id=$scenarioId;properties=@{actions=@(@{actionId='urn:csci:microsoft:virtualmachinescaleset:shutdown/1.0.0';duration='PT7M'
    parameters=@(@{key='GracefulShutdown';value='false'},@{key='Zones';value='[]'})})}}
$config=@{id="$scenarioId/configurations/owned";properties=@{scenarioId=$scenarioId;resourceTargeting=@{include=@{resources=@($target)}}}}
Assert-AksNativeDefinition $config $scenario @($target) node
$scenario.properties.actions[0].actionId='microsoft-virtualmachinescaleset-shutdown/1.0'
Assert-AksNativeDefinition $config $scenario @($target) node
function Reject([scriptblock] $Action){
    $rejected=$false
    try{& $Action}catch{$rejected=$true}
    if(-not $rejected){throw 'Unsafe native contract unexpectedly accepted.'}
}
$scenario.properties.actions[0].duration='PT5M'
Reject {Assert-AksNativeDefinition $config $scenario @($target) node}
$scenario.properties.actions[0].duration='PT7M'
$scenario.properties.actions[0].parameters[0].value='true'
Reject {Assert-AksNativeDefinition $config $scenario @($target) node}
$scenario.properties.actions[0].parameters[0].value='false'
$targets=@($target,"$prefix/providers/Microsoft.Compute/virtualMachineScaleSets/two","$prefix/providers/Microsoft.Compute/virtualMachineScaleSets/three")
$config.properties.resourceTargeting.include.resources=$targets
$scenario.properties.actions[0].parameters[1].value='["1"]'
Assert-AksNativeDefinition $config $scenario $targets zone
$scenario.properties.actions[0].parameters[1].value='["2"]'
Reject {Assert-AksNativeDefinition $config $scenario $targets zone}
$scenario.properties.actions[0].parameters[1].value='["1"]'
$config.properties.resourceTargeting.include.resources=@($targets[0],$targets[1])
Reject {Assert-AksNativeDefinition $config $scenario $targets zone}
'AKS exact owned native targets, abrupt duration and serialized zone-selector contract tests passed.'
