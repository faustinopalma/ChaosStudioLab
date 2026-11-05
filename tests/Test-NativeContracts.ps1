$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\scripts\Lab.Native.ps1')
$script:LabSubscription='00000000-0000-0000-0000-000000000001'
$script:LabGroups=@('rg-fixture-net','rg-fixture-work','rg-fixture-ops')
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1'),[ref]$tokens,[ref]$errors)
foreach($name in @('Assert-LabResourceId','Write-LabJson')) {
    $definition=$ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    . ([scriptblock]::Create($definition[0].Extent.Text))
}
function Expect-Rejected([scriptblock]$Action) {
    $caught=$false
    try { & $Action | Out-Null } catch { $caught=$true }
    if(-not $caught) { throw 'An unsafe or ambiguous native contract was accepted.' }
}
$scope="/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])/providers"
$scenarioId="$scope/Microsoft.Chaos/workspaces/fixture/scenarios/instance"
$appId="$scope/Microsoft.Web/sites/fixture"
$scenario=@{id=$scenarioId;properties=@{actions=@(@{
    actionId='urn:csci:microsoft:appservice:killprocess/1.0.0'
    parameters=@(@{key='ProcessName';value='dotnet'},@{key='InstanceIds';value='["instance-a"]'},@{key='Zones';value='[]'})
})}}
$configuration=@{id="$scenarioId/configurations/exact";properties=@{scenarioId=$scenarioId;resourceTargeting=@{include=@{resources=@($appId)}}}}
Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a
$namedParameters=$scenario.properties.actions[0].parameters
$scenario.properties.actions[0].parameters=@($namedParameters|Where-Object key -ne ProcessName)
Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a
$scenario.properties.actions[0].parameters+=@(@{key='Unexpected';value='not-allowed'})
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$scenario.properties.actions[0].parameters=$namedParameters
$configuration.properties.scenarioId='instance'
Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a
if((Get-LabNativeScenarioId $configuration) -cne $scenarioId) { throw 'Provider short Scenario name was not resolved against its exact owned parent.' }
$configuration.properties.scenarioId='other'
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$configuration.properties.scenarioId=$scenarioId
$scenario.properties.actions[0].actionId='microsoft-appservice-killprocess/1.0'
Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a
if((Get-LabNativeActionUrn 'microsoft-azurepostgresql-failover/1.0') -cne 'urn:csci:microsoft:azurepostgresql:failover/1.0.0') {
    throw 'Observed native PostgreSQL Action identifier lost its canonical fault mapping.'
}
Expect-Rejected { Get-LabNativeActionUrn 'microsoft-appservice-killprocess/2.0' }
$scenario.properties.actions[0].parameters[0].value=''
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$scenario.properties.actions[0].parameters[0].value='dotnet'
$scenario.properties.actions[0].parameters[1].value='[]'
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$scenario.properties.actions[0].parameters[2].value='["2"]'
Assert-LabNativeConfiguration $configuration $scenario $appId zone 2
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId zone 1 }
$scenario.properties.actions[0].parameters[1].value='["instance-a"]'
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId zone 2 }
$scenario.properties.actions[0].parameters[2].value='[]'
$scenario.properties.actions[0].parameters[1].value='"instance-a"'
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$scenario.properties.actions[0].parameters[1].value='["instance-a"]'
$configuration.properties.resourceTargeting.include.resources+=@("$scope/Microsoft.Web/sites/other")
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$configuration.properties.resourceTargeting.include.resources=@($appId)
$poll="https://management.azure.com$scenarioId/runs/fixture?api-version=2026-08-01-preview"
if((Get-LabNativePollUri @{headers=@{Location=@($poll)};body=$null}) -ne $poll) { throw 'Valid owned Location was lost.' }
foreach($address in @($poll.Replace('https:','http:'),$poll.Replace('management.azure.com','example.invalid'),
    "$poll#fragment",$poll.Replace('rg-fixture-work','rg-unrelated'))) {
    Expect-Rejected { Get-LabNativePollUri @{headers=@{Location=$address};body=$null} }
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) "csl-native-contract-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $fixture | Out-Null
$nativeFixture=@{response=@{statusCode=200;headers=@{};body=@{properties=@{status='Succeeded'}}};fail=$false;activityQueries=0;activityDelay=0;auditSleeps=0}
function Invoke-LabArm {
    param($Method,$Uri,$Body)
    if($nativeFixture.fail) { throw 'Fixture native submission transport uncertainty.' }
    if($Method -eq 'Post' -and $Uri -match '/validate\?') {
        return @{statusCode=202;headers=@{Location=$poll};body=$null}
    }
    return $nativeFixture.response
}
function Invoke-LabAz {
    param([string[]] $Arguments)
    $nativeFixture.activityQueries++
    if($nativeFixture.activityDelay -gt 0) {
        $nativeFixture.activityDelay--
        return ConvertTo-Json -InputObject @($nativeFixture.activityEvents | Where-Object { $_.status.value -ne 'Succeeded' }) -Depth 20
    }
    return ConvertTo-Json -InputObject $nativeFixture.activityEvents -Depth 20
}
function Start-Sleep {
    param([int] $Seconds)
    $nativeFixture.auditSleeps++
}
try {
    Wait-LabNativeOperation $poll (Join-Path $fixture 'operation') -TimeoutSeconds 1 | Out-Null
    $nativeFixture.response.body.properties.status='Failed'
    Expect-Rejected { Wait-LabNativeOperation $poll (Join-Path $fixture 'failed') -TimeoutSeconds 1 }
    $nativeFixture.response.body.properties=@{status='Succeeded';resources=@(@{id=$appId});errors=@();validationErrors=$null}
    Confirm-LabNativeValidation $configuration.id $appId (Join-Path $fixture 'validation') | Out-Null
    $nativeFixture.response.body.properties.Remove('validationErrors')
    Confirm-LabNativeValidation $configuration.id $appId (Join-Path $fixture 'validation-without-optional-errors') | Out-Null
    $nativeFixture.response.body.properties.resources[0].id="$scope/Microsoft.Web/sites/other"
    Expect-Rejected { Confirm-LabNativeValidation $configuration.id $appId (Join-Path $fixture 'wrong-validation-target') }
    $nativeFixture.response.body.properties.resources[0].id=$appId
    $nativeFixture.response.body.properties.status='RequiresAttention'
    Expect-Rejected { Confirm-LabNativeValidation $configuration.id $appId (Join-Path $fixture 'requires-attention') }
    Expect-Rejected { Wait-LabNativeOperation $poll (Join-Path $fixture 'execution-requires-attention') -TimeoutSeconds 1 -AllowFailedTerminal }
    $nativeFixture.response.body.properties.status='Succeeded'
    $nativeFixture.response.body.properties.validationErrors=@{permission=@();resource=@(@{errorCode=-1})}
    Expect-Rejected { Confirm-LabNativeValidation $configuration.id $appId (Join-Path $fixture 'validation-errors') }
    $manifest=@{}
    $path=Join-Path $fixture 'manifest.json'
    $nativeFixture.fail=$true
    Expect-Rejected { Start-LabNativeExecution "$scenarioId/configurations/exact" $manifest $path (Join-Path $fixture 'submission') }
    $saved=Get-Content $path -Raw | ConvertFrom-Json
    if($saved.activeNativeOperations.Count -ne 1 -or $saved.activeNativeOperations[0].status -ne 'SUBMISSION_FAILED_OR_UNCERTAIN') {
        throw 'An uncertain native submission was not retained to prevent an accidental duplicate fault.'
    }
    $nativeFixture.fail=$false
    $principal='00000000-0000-0000-0000-000000000002'
    $parameters=@{}
    foreach($p in $scenario.properties.actions[0].parameters) { $parameters[$p.key]=$p.value }
    $compiled=@{actions=@{kill=@{properties=@{faultUrn=(Get-LabNativeActionUrn $scenario.properties.actions[0].actionId)
        faultParameters=$parameters;targetResources=@(@{fullyQualifiedIdentifier=$appId})}}}}
    $nativeFixture.response.body=@{properties=@{
        status='Succeeded';managedIdentityPrincipalId=$principal;resources=@(@{id=$appId});errors=@()
        scenarioRunJson=($compiled | ConvertTo-Json -Depth 15 -Compress);scenarioRunSummary=@(@{state='Succeeded'})
    }}
    $intent=@{pollUri=$poll;status='ACCEPTED'}
    $manifest=@{activeNativeOperations=@($intent)}
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'verified') $scenario $appId $principal | Out-Null
    if($intent.status -ne 'SUCCEEDED') { throw 'Fully verified native terminal success was not reconciled.' }
    $nativeFixture.response.body.properties.managedIdentityPrincipalId='wrong-principal'
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'wrong-identity') $scenario $appId $principal }
    if($intent.status -ne 'TERMINAL_UNVERIFIED') { throw 'Unverified native success was incorrectly cleared for another fault.' }
    $pgId="$scope/Microsoft.DBforPostgreSQL/flexibleServers/fixture"
    $pgScenario=@{properties=@{actions=@(@{actionId='microsoft-azurepostgresql-failover/1.0';parameters=@(
        @{key='FailoverMode';value='1'},@{key='RestoreOnStop';value='false'},@{key='SkipIneligibleServers';value='false'}
    )})}}
    $pgParameters=@{}
    foreach($p in $pgScenario.properties.actions[0].parameters) { $pgParameters[$p.key]=$p.value }
    $nativeFixture.response.body.properties=@{
        status='Succeeded';managedIdentityPrincipalId='misreported';resources=@(@{id=$pgId});errors=@()
        startTime='2026-11-05T08:00:00Z';endTime='2026-11-05T08:02:00Z'
        scenarioRunJson=(@{actions=@{failover=@{properties=@{faultUrn='urn:csci:microsoft:azurepostgresql:failover/1.0.0'
            faultParameters=$pgParameters;targetResources=@(@{fullyQualifiedIdentifier=$pgId})}}}} | ConvertTo-Json -Depth 15 -Compress)
        scenarioRunSummary=@(@{state='Succeeded'})
    }
    $nativeFixture.activityEvents=@(
        @{resourceId=$pgId;operationName=@{value='Microsoft.DBforPostgreSQL/flexibleServers/restart/action'}
            eventTimestamp='2026-11-05T08:00:20Z';status=@{value='Started'};correlationId='same-operation'
            httpRequest=@{clientRequestId='same-request'};caller=$principal
            claims=@{'http://schemas.microsoft.com/identity/claims/objectidentifier'=$principal}},
        @{resourceId=$pgId;operationName=@{value='Microsoft.DBforPostgreSQL/flexibleServers/restart/action'}
            eventTimestamp='2026-11-05T08:01:00Z';status=@{value='Succeeded'};correlationId='same-operation'
            httpRequest=@{clientRequestId='same-request'};caller=$principal
            claims=@{'http://schemas.microsoft.com/identity/claims/objectidentifier'=$principal}}
    )
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'audited-pg') $pgScenario $pgId $principal | Out-Null
    if($intent.status -ne 'SUCCEEDED' -or -not (Test-Path (Join-Path $fixture 'audited-pg-identity-proof.json'))) {
        throw 'Independently authenticated native PostgreSQL completion was not reconciled.'
    }
    $queryCount=$nativeFixture.activityQueries
    $sleepCount=$nativeFixture.auditSleeps
    $nativeFixture.activityDelay=1
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'delayed-pg') $pgScenario $pgId $principal | Out-Null
    if($nativeFixture.activityQueries -ne $queryCount+2 -or $nativeFixture.auditSleeps -ne $sleepCount+1 -or
        -not (Test-Path (Join-Path $fixture 'delayed-pg-identity-activity-000.json')) -or
        -not (Test-Path (Join-Path $fixture 'delayed-pg-identity-activity-001.json'))) {
        throw 'Delayed Activity Log completion was not boundedly retried with both original snapshots retained.'
    }
    $savedEvents=$nativeFixture.activityEvents
    $nativeFixture.activityEvents=@()
    $queryCount=$nativeFixture.activityQueries
    $sleepCount=$nativeFixture.auditSleeps
    Expect-Rejected { Confirm-LabNativePostgresIdentity $nativeFixture.response.body $pgScenario $pgId $principal (Join-Path $fixture 'expired-pg-audit') -AuditTimeoutSeconds 0 }
    if($nativeFixture.activityQueries -ne $queryCount+1 -or $nativeFixture.auditSleeps -ne $sleepCount) {
        throw 'Expired audit visibility deadline did not fail closed after its final query.'
    }
    $nativeFixture.activityEvents=$savedEvents
    $nativeFixture.activityEvents[1].Remove('httpRequest')
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'audited-pg-without-terminal-http') $pgScenario $pgId $principal | Out-Null
    $foreignPgId=$pgId -replace '/resourceGroups/[^/]+/','/resourceGroups/foreign/'
    $queryCount=$nativeFixture.activityQueries
    Expect-Rejected { Confirm-LabNativePostgresIdentity $nativeFixture.response.body $pgScenario $foreignPgId $principal (Join-Path $fixture 'foreign-pg-audit') }
    if($nativeFixture.activityQueries -ne $queryCount) { throw 'Foreign native identity-audit target reached Azure before ownership rejection.' }
    $nativeFixture.activityEvents[1].httpRequest=@{clientRequestId='same-request'}
    $nativeFixture.activityEvents[1].caller='other'
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'wrong-pg-caller') $pgScenario $pgId $principal }
    $nativeFixture.activityEvents[1].caller=$principal
    $nativeFixture.activityEvents[1].claims['http://schemas.microsoft.com/identity/claims/objectidentifier']='other'
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'wrong-pg-claim') $pgScenario $pgId $principal }
    $nativeFixture.activityEvents[1].claims['http://schemas.microsoft.com/identity/claims/objectidentifier']=$principal
    $nativeFixture.activityEvents[1].httpRequest.clientRequestId='different'
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'uncorrelated-pg') $pgScenario $pgId $principal }
    $nativeFixture.activityEvents[1].httpRequest.clientRequestId='same-request'
    $nativeFixture.activityEvents+=@($nativeFixture.activityEvents[1].Clone())
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'ambiguous-pg') $pgScenario $pgId $principal }
    $nativeFixture.activityEvents=@($nativeFixture.activityEvents[1])
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'missing-pg-start') $pgScenario $pgId $principal }
    'Native exact targets, serialized non-random selectors, secure owned polling, explicit failures and uncertain submissions verified.'
} finally { Remove-Item -LiteralPath $fixture -Recurse }
