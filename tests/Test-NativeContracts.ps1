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
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
$scenario.properties.actions[0].parameters=@($namedParameters|ForEach-Object { if($_.key -eq 'ProcessName') { @{key='ProcessName';value='w3wp'} } else { $_ } })
Expect-Rejected { Assert-LabNativeConfiguration $configuration $scenario $appId instance instance-a }
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
$nativeFixture=@{response=@{statusCode=200;headers=@{};body=@{properties=@{status='Succeeded'}}};fail=$false;activityQueries=0;activityDelay=0;auditSleeps=0
    processQueries=0;processes=@{}
    discoveries=0;discovered=@();workspaceScopes=@("/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])")}
function Invoke-LabArm {
    param($Method,$Uri,$Body)
    if($nativeFixture.fail) { throw 'Fixture native submission transport uncertainty.' }
    if($Method -eq 'Post' -and $Uri -match '/validate\?') {
        return @{statusCode=202;headers=@{Location=$poll};body=$null}
    }
    if($Method -eq 'Post' -and $Uri -match '/discover\?') {
        $nativeFixture.discoveries++
        return @{statusCode=202;headers=@{Location=$poll};body=$null}
    }
    if($Method -eq 'Get' -and $Uri -match '/discoveredResources\?') {
        return @{statusCode=200;headers=@{};body=@{value=@($nativeFixture.discovered | ForEach-Object {
            @{properties=@{fullyQualifiedIdentifier=$_}} })}}
    }
    if($Method -eq 'Get' -and $Uri -match '/instances/(?<instance>[^/]+)/processes(/(?<process>[0-9]+))?\?') {
        $nativeFixture.processQueries++
        $listed=@($nativeFixture.processes[$Matches.instance])
        if($Matches.ContainsKey('process')) {
            $process=@($listed | Where-Object pid -eq $Matches.process)[0]
            $properties=@{name=$process.name}
            # Like the live API, non-SCM processes omit is_scm_site entirely.
            if($process.scm) { $properties.is_scm_site=$true }
            return @{statusCode=200;headers=@{};body=@{properties=$properties}}
        }
        return @{statusCode=200;headers=@{};body=@{value=@($listed | ForEach-Object {
            @{name="fixture/$($Matches.instance)/$($_.pid)";properties=@{name=$_.name}} })}}
    }
    if($Method -eq 'Get' -and $Uri -match '/workspaces/fixture\?') {
        return @{statusCode=200;headers=@{};body=@{properties=@{scopes=@($nativeFixture.workspaceScopes)}}}
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
    $validationProperties=$nativeFixture.response.body.properties
    $nativeFixture.response.body.properties=@{status='Succeeded'}
    $workspaceId="$scope/Microsoft.Chaos/workspaces/fixture"
    $databaseId="$scope/Microsoft.DBforPostgreSQL/flexibleServers/fixture"
    $nativeFixture.discovered=@($appId,$databaseId,"$scope/Microsoft.Web/sites/other")
    $found=@(Find-LabNativeTargets $workspaceId @($appId,$databaseId) $fixture)
    if($found.Count -ne 2 -or $nativeFixture.discoveries -ne 1) { throw 'Native discovery refresh did not expose exactly the owned targets.' }
    $nativeFixture.discovered=@($databaseId)
    Expect-Rejected { Find-LabNativeTargets $workspaceId @($appId) $fixture }
    $nativeFixture.discovered=@($appId,$appId)
    Expect-Rejected { Find-LabNativeTargets $workspaceId @($appId) $fixture }
    $nativeFixture.discovered=@($appId)
    $nativeFixture.workspaceScopes=@("/subscriptions/$script:LabSubscription/resourceGroups/rg-unrelated")
    Expect-Rejected { Find-LabNativeTargets $workspaceId @($appId) $fixture }
    $nativeFixture.workspaceScopes=@("/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])")
    $nativeFixture.response.body.properties=$validationProperties
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
    $queryCount=$nativeFixture.activityQueries
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'verified') $scenario $appId $principal }
    if($intent.status -ne 'TERMINAL_UNVERIFIED' -or $nativeFixture.activityQueries -ne $queryCount) {
        throw 'An App Service completion without a pre-selected application process was accepted or queried Azure.'
    }
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
    $nativeFixture.activityEvents[1].eventTimestamp='2026-11-05T08:02:35Z'
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'later-provider-completion') $pgScenario $pgId $principal | Out-Null
    $proof=Get-Content (Join-Path $fixture 'later-provider-completion-identity-proof.json') -Raw|ConvertFrom-Json
    if($proof.providerCompletionLagSeconds -ne 35) { throw 'The separately correlated provider completion lag was not retained.' }
    $nativeFixture.activityEvents[0].eventTimestamp='2026-11-05T08:02:00.001Z'
    Expect-Rejected { Confirm-LabNativePostgresIdentity $nativeFixture.response.body $pgScenario $pgId $principal (Join-Path $fixture 'late-start') -AuditTimeoutSeconds 0 }
    $nativeFixture.activityEvents[0].eventTimestamp='2026-11-05T08:00:20Z'
    $nativeFixture.activityEvents[1].eventTimestamp='2026-11-05T08:17:00Z'
    Confirm-LabNativePostgresIdentity $nativeFixture.response.body $pgScenario $pgId $principal (Join-Path $fixture 'completion-boundary') -AuditTimeoutSeconds 0
    $nativeFixture.activityEvents[1].eventTimestamp='2026-11-05T08:17:00.001Z'
    Expect-Rejected { Confirm-LabNativePostgresIdentity $nativeFixture.response.body $pgScenario $pgId $principal (Join-Path $fixture 'expired-completion') -AuditTimeoutSeconds 0 }
    $nativeFixture.activityEvents[1].eventTimestamp='2026-11-05T08:01:00Z'
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
    $appCompiled=@{actions=@{kill=@{properties=@{faultUrn=(Get-LabNativeActionUrn $scenario.properties.actions[0].actionId)
        faultParameters=$parameters;targetResources=@(@{fullyQualifiedIdentifier=$appId})}}}}
    $nativeFixture.response.body.properties=@{
        status='Succeeded';managedIdentityPrincipalId='misreported';resources=@(@{id=$appId});errors=@()
        startTime='2026-11-05T09:00:00Z';endTime='2026-11-05T09:00:10Z'
        scenarioRunJson=($appCompiled | ConvertTo-Json -Depth 15 -Compress);scenarioRunSummary=@(@{state='Succeeded'})
    }
    function New-ProcessDeleteEvent([string]$Instance,[string]$Status,[string]$Timestamp,[string]$Correlation) {
        @{resourceId="$appId/instances/$Instance/processes/2800";operationName=@{value='Microsoft.Web/sites/instances/processes/delete'}
            eventTimestamp=$Timestamp;status=@{value=$Status};correlationId=$Correlation
            httpRequest=@{clientRequestId="request-$Correlation"};caller=$principal
            claims=@{'http://schemas.microsoft.com/identity/claims/objectidentifier'=$principal}}
    }
    $nativeFixture.activityDelay=0
    $nativeFixture.activityEvents=@(
        (New-ProcessDeleteEvent 'instance-a' 'Started' '2026-11-05T09:00:07.6Z' 'kill-a'),
        (New-ProcessDeleteEvent 'instance-a' 'Succeeded' '2026-11-05T09:00:07.9Z' 'kill-a'))
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'audited-app') $scenario $appId $principal @('instance-a') @{'instance-a'='2800'} | Out-Null
    $proof=Get-Content (Join-Path $fixture 'audited-app-identity-proof.json') -Raw | ConvertFrom-Json
    if($intent.status -ne 'SUCCEEDED' -or $proof.processDeletions.Count -ne 1 -or $proof.processDeletions[0].processId -ne '2800') {
        throw 'Independently authenticated native App Service process deletion was not reconciled.'
    }
    $nativeFixture.response.body.properties.managedIdentityPrincipalId=$principal
    $queryCount=$nativeFixture.activityQueries
    Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'audited-app-matching-principal') $scenario $appId $principal @('instance-a') @{'instance-a'='2800'} | Out-Null
    if($intent.status -ne 'SUCCEEDED' -or $nativeFixture.activityQueries -ne $queryCount+1) {
        throw 'An App Service completion with matching principal metadata skipped the process identity audit.'
    }
    $nativeFixture.response.body.properties.managedIdentityPrincipalId='misreported'
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'app-scm-process') $scenario $appId $principal @('instance-a') @{'instance-a'='6536'} }
    if($intent.status -ne 'TERMINAL_UNVERIFIED') { throw 'A deletion of a process other than the pre-selected application process was reconciled.' }
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'app-without-selection') $scenario $appId $principal }
    Expect-Rejected { Complete-LabNativeExecution $intent $manifest $path (Join-Path $fixture 'app-without-process') $scenario $appId $principal @('instance-a') }
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-process-map-mismatch') -ExpectedInstanceIds @('instance-a') -ExpectedProcessIds @{'instance-b'='2800'} -AuditTimeoutSeconds 0 }
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-missing-instance') -ExpectedInstanceIds @('instance-a','instance-b') -ExpectedProcessIds @{'instance-a'='2800';'instance-b'='2800'} -AuditTimeoutSeconds 0 }
    $zoneEvents=$nativeFixture.activityEvents+@(
        (New-ProcessDeleteEvent 'instance-b' 'Started' '2026-11-05T09:00:08.1Z' 'kill-b'),
        (New-ProcessDeleteEvent 'instance-b' 'Succeeded' '2026-11-05T09:00:08.4Z' 'kill-b'))
    $nativeFixture.activityEvents=$zoneEvents
    Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-zone') -ExpectedInstanceIds @('instance-a','instance-b') -ExpectedProcessIds @{'instance-a'='2800';'instance-b'='2800'} -AuditTimeoutSeconds 0
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-outside-selection') -ExpectedInstanceIds @('instance-a') -ExpectedProcessIds @{'instance-a'='2800'} -AuditTimeoutSeconds 0 }
    $nativeFixture.activityEvents=@($zoneEvents[0],$zoneEvents[1])
    $nativeFixture.activityEvents[1].caller='other'
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-wrong-caller') -ExpectedInstanceIds @('instance-a') -ExpectedProcessIds @{'instance-a'='2800'} -AuditTimeoutSeconds 0 }
    $nativeFixture.activityEvents[1].caller=$principal
    $nativeFixture.activityEvents[0].eventTimestamp='2026-11-05T09:00:08Z'
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-unordered') -ExpectedInstanceIds @('instance-a') -ExpectedProcessIds @{'instance-a'='2800'} -AuditTimeoutSeconds 0 }
    $nativeFixture.activityEvents[0].eventTimestamp='2026-11-05T09:00:07.6Z'
    $nativeFixture.activityEvents=@($nativeFixture.activityEvents[1])
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $scenario $appId $principal (Join-Path $fixture 'app-missing-start') -ExpectedInstanceIds @('instance-a') -ExpectedProcessIds @{'instance-a'='2800'} -AuditTimeoutSeconds 0 }
    Expect-Rejected { Confirm-LabNativeAppServiceIdentity $nativeFixture.response.body $pgScenario $appId $principal (Join-Path $fixture 'app-wrong-action') -ExpectedInstanceIds @('instance-a') -ExpectedProcessIds @{'instance-a'='2800'} -AuditTimeoutSeconds 0 }
    $nativeFixture.processes=@{
        'instance-a'=@(@{pid='6220';name='w3wp';scm=$true},@{pid='7832';name='w3wp';scm=$false},@{pid='5100';name='dotnet';scm=$false})
        'instance-b'=@(@{pid='4100';name='dotnet';scm=$false})
    }
    $selected=Get-LabNativeApplicationProcesses $appId @('instance-a','instance-b') dotnet (Join-Path $fixture 'app-processes')
    if($selected.Count -ne 2 -or $selected['instance-a'] -cne '5100' -or $selected['instance-b'] -cne '4100' -or
        -not (Test-Path (Join-Path $fixture 'app-processes-instance-a-process-5100.json'))) {
        throw 'The exact non-SCM dotnet application process was not selected and retained per instance.'
    }
    $nativeFixture.processes['instance-b']=@(@{pid='4100';name='dotnet';scm=$true})
    Expect-Rejected { Get-LabNativeApplicationProcesses $appId @('instance-b') dotnet (Join-Path $fixture 'app-processes-scm') }
    $nativeFixture.processes['instance-b']=@(@{pid='4100';name='dotnet';scm=$false},@{pid='4200';name='dotnet';scm=$false})
    Expect-Rejected { Get-LabNativeApplicationProcesses $appId @('instance-b') dotnet (Join-Path $fixture 'app-processes-ambiguous') }
    $nativeFixture.processes['instance-b']=@(@{pid='7000';name='w3wp';scm=$false})
    Expect-Rejected { Get-LabNativeApplicationProcesses $appId @('instance-b') dotnet (Join-Path $fixture 'app-processes-missing') }
    $queryCount=$nativeFixture.processQueries
    Expect-Rejected { Get-LabNativeApplicationProcesses $appId @('instance-b') w3wp (Join-Path $fixture 'app-processes-wrong-name') }
    Expect-Rejected { Get-LabNativeApplicationProcesses $appId @('../instance-b') dotnet (Join-Path $fixture 'app-processes-invalid') }
    if($nativeFixture.processQueries -ne $queryCount) { throw 'Unsafe process selection input reached Azure.' }
    'Native exact targets, serialized non-random selectors, exact application-process selection and audit, secure owned polling, explicit failures and uncertain submissions verified.'
} finally { Remove-Item -LiteralPath $fixture -Recurse }
