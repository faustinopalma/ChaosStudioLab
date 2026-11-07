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
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\scripts\Test-AksLab.ps1'),[ref]$tokens,[ref]$errors)
if($errors){throw 'AKS orchestration parsing failed.'}
$assignment=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -eq 'targetVms'
},$true))
if($assignment.Count -ne 1){throw 'Exact actual VM selection is ambiguous.'}
$compute=$true
$initial=@{vms=@(@{id='vm-one';scaleSetId=$targets[0];zones=@('1')},@{id='vm-two';scaleSetId=$targets[1];zones=@('1')},@{id='vm-three';scaleSetId=$targets[2];zones=@('1')})}
$computeDefinition=@{kind='node';targets=@($targets[0])}
. ([scriptblock]::Create($assignment[0].Extent.Text))
if($targetVms -isnot [array] -or $targetVms.Count -ne 1 -or $targetVms[0] -ne 'vm-one'){throw 'Actual singleton node target lost its explicit collection shape.'}
$computeDefinition=@{kind='zone';targets=$targets}
. ([scriptblock]::Create($assignment[0].Extent.Text))
if($targetVms.Count -ne 3){throw 'Actual selected-zone VM set is incomplete.'}
$aggregate=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and
    $node.Extent.Text.StartsWith('if($run.status -ne',[StringComparison]::Ordinal) -and
    $node.Extent.Text.Contains('$report.status=')
},$true))
if($aggregate.Count -ne 1){throw 'Actual full-phase verdict aggregation is ambiguous.'}
foreach($case in @(
    @{phase='PASS';effect='PASS';expected='PASS'},
    @{phase='FAIL';effect='PASS';expected='FAIL'},
    @{phase='FAIL';effect='INCONCLUSIVE';expected='INCONCLUSIVE'},
    @{phase='PASS';effect='FAIL';expected='FAIL'}
)){
    $run=@{status=$case.phase}
    $report=@{status=$case.effect;reason='fixture';effect=@{status=$case.effect;reason='fixture'}}
    . ([scriptblock]::Create($aggregate[0].Extent.Text))
    if($report.status -ne $case.expected){throw 'Actual entrypoint hid a failed full-phase or effect verdict.'}
}
$evaluation=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.CommandElements[0].Extent.Text -like '*evaluate-aks.ps1*'
},$true))
$after=@($ast.FindAll({param($node)
    $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Qualify' -and
    $node.CommandElements.Count -eq 2 -and $node.CommandElements[1].Extent.Text -eq 'after'
},$true))
if($evaluation.Count -ne 1 -or @($after|Where-Object {$_.Extent.StartOffset -gt $evaluation[0].Extent.EndOffset}).Count -ne 1){
    throw 'Independent measurement effects must be evaluated before final baseline-layout qualification.'
}
'AKS exact owned native targets, abrupt duration and serialized zone-selector contract tests passed.'
