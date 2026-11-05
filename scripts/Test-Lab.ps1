[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [ValidateSet('BASE-001', 'HA-APP-001', 'HA-APP-ZONE-001', 'HA-DB-001', 'HA-COMBINED-001', 'HA-AZ-001')]
    [string] $TestId = 'BASE-001',
    [ValidateRange(1,65535)][int] $TunnelPort = 50222
)
if(-not $env:CSL_ENVIRONMENT_FILE) { throw 'Select the approved private environment explicitly.' }
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
. (Join-Path $PSScriptRoot 'Lab.Native.ps1')
Confirm-LabContext
$ManifestPath=[IO.Path]::GetFullPath($ManifestPath)
$m=Read-LabManifest $ManifestPath
$stateRoot=Split-Path $ManifestPath -Parent
$caseId=[Guid]::NewGuid().ToString('N')
$caseRoot=Join-Path $stateRoot "tests\$TestId-$caseId"
New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
$started=[DateTimeOffset]::UtcNow
$report=@{schemaVersion=1;testId=$TestId;caseId=$caseId;status='INCONCLUSIVE'
    startedAtUtc=$started.ToString('O');reason=$null;phases=@();automaticAzureCleanup=$false}
$lock=[IO.File]::Open("$ManifestPath.lock",'OpenOrCreate','ReadWrite','None')
$sshOptions=@(Get-LabSshOptions $m $stateRoot)
$sshArgs=$sshOptions+@('-p',[string]$TunnelPort,'csloperator@127.0.0.1')
$managementSession=$null
function Invoke-PrivateQualification([string]$Label) {
    $name="qualification-$caseId-$Label.json"
    & ssh @sshArgs "cd ~/csl && timeout 330 pwsh -NoLogo -NoProfile -File scripts/runner/qualify-app.ps1 -OutputPath results/$name"
    if($LASTEXITCODE -ne 0) { throw 'Private application health/business/process qualification failed.' }
    $path=Join-Path $caseRoot $name
    & scp @sshOptions -P $TunnelPort "csloperator@127.0.0.1:csl/results/$name" $path
    if($LASTEXITCODE -ne 0) { throw 'Private participation proof retrieval failed.' }
    $proof=Get-Content $path -Raw | ConvertFrom-Json
    $instances=Invoke-LabAz @('rest','--method','get','--url',
        "https://management.azure.com$($w.applicationId)/instances?api-version=2025-03-01",'-o','json') | ConvertFrom-Json -AsHashtable
    Write-LabJson (Join-Path $caseRoot "$Label-instances.json") $instances
    Assert-LabAppServicePlacement $plan $instances.value $proof.observations
    return @{instances=$instances.value;observations=$proof.observations}
}
function Start-PrivateMeasurement([string]$Phase,[string]$Duration,[string]$RunId) {
    Start-PrivateCommand $Phase $RunId "cd ~/csl && timeout 1800 pwsh -NoLogo -NoProfile -File scripts/runner/test.ps1 -Phase $Phase -Duration $Duration -RunId $RunId > $Phase-$RunId.log 2>&1"
}
function Start-PrivateCommand([string]$Phase,[string]$RunId,[string]$Command) {
    $start=[Diagnostics.ProcessStartInfo]::new((Get-Command ssh -ErrorAction Stop).Source)
    foreach($argument in $sshArgs) { $start.ArgumentList.Add($argument) }
    $start.ArgumentList.Add($Command)
    $start.UseShellExecute=$false
    $start.RedirectStandardOutput=$true
    $start.RedirectStandardError=$true
    $start.RedirectStandardInput=$true
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=$start
    if(-not $process.Start()) { throw 'Private foreground measurement SSH did not start.' }
    return @{process=$process;stdout=$process.StandardOutput.ReadToEndAsync();stderr=$process.StandardError.ReadToEndAsync()
        runId=$RunId;phase=$Phase;startedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}
}
function Complete-PrivateObserver([hashtable]$Observer) {
    try {
        if(-not $Observer.process.WaitForExit(1830000)) {
            Stop-Process -Id $Observer.process.Id -Force
            throw 'Private independent observer exceeded its deadline; its guest timeout remains enforced.'
        }
        $Observer.stdout.GetAwaiter().GetResult() | Set-Content (Join-Path $caseRoot 'observer-ssh.stdout.log')
        $Observer.stderr.GetAwaiter().GetResult() | Set-Content (Join-Path $caseRoot 'observer-ssh.stderr.log')
        if($Observer.process.ExitCode -ne 0) { throw 'Independent private observer failed; inspect its explicit SSH logs.' }
    } finally { $Observer.process.Dispose() }
}
function Confirm-AllWriteHistory {
    $time=[DateTimeOffset]::UtcNow
    & ssh @sshArgs "cd ~/csl && timeout 3600 pwsh -NoLogo -NoProfile -File scripts/runner/verify.ps1 -VerifyAllRuns > all-history-$caseId.log 2>&1"
    $exitCode=$LASTEXITCODE
    & scp @sshOptions -P $TunnelPort 'csloperator@127.0.0.1:csl/results/all-runs-durability.json' (Join-Path $caseRoot 'all-runs-durability.json')
    if($LASTEXITCODE -ne 0) { throw 'Full write-history evidence retrieval failed.' }
    $history=Get-Content (Join-Path $caseRoot 'all-runs-durability.json') -Raw | ConvertFrom-Json
    $report.retentionReconciliationSeconds=([DateTimeOffset]::UtcNow-$time).TotalSeconds
    if($exitCode -ne 0 -or $history.status -ne 'PASS' -or
        @($history.runs | Where-Object { $_.status -ne 'PASS' -or $_.lostAcknowledgedWrites -ne 0 }).Count) {
        throw 'Full write-history reconciliation failed or exceeded its one-hour deadline; prior writes remain explicitly unqualified.'
    }
    $report.retention=$history
}
function Get-VerifiedNativeDefinition([string]$ConfigurationId,[string]$TargetId,[string]$Kind,[string]$Selector) {
    $configuration=(Invoke-LabArm Get "https://management.azure.com${ConfigurationId}?api-version=2026-08-01-preview").body
    $scenario=(Invoke-LabArm Get "https://management.azure.com$($configuration.properties.scenarioId)?api-version=2026-08-01-preview").body
    Assert-LabNativeConfiguration $configuration $scenario $TargetId $Kind $Selector
    Write-LabJson (Join-Path $caseRoot "$Kind-definition.json") @{configuration=$configuration;scenario=$scenario}
    return @{configuration=$configuration;scenario=$scenario;targetId=$TargetId;kind=$Kind}
}
function Invoke-SelectedNative([hashtable]$Definition) {
    Start-LabNativeExecution $Definition.configuration.id $m $ManifestPath (Join-Path $caseRoot $Definition.kind)
}
function Complete-SelectedNative([hashtable]$Intent,[hashtable]$Definition) {
    $result=Complete-LabNativeExecution $Intent $m $ManifestPath (Join-Path $caseRoot $Definition.kind) `
        $Definition.scenario $Definition.targetId $nativePrincipal
    if($Definition.kind -eq 'postgres') {
        $m.lastPostgresFaultFinishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        Write-LabJson $ManifestPath $m
    }
    return $result
}
function Invoke-NativeCase {
    if(-not $m.ContainsKey('lastBaseline') -or $m.lastBaseline.status -ne 'PASS' -or
        $m.lastBaseline.packageSha256 -cne $m.applicationPackageSha256 -or
        ([DateTimeOffset]::UtcNow-[DateTimeOffset]$m.lastBaseline.completedAtUtc).TotalHours -gt 4 -or
        @(Compare-Object @($m.lastBaseline.instanceIds | Sort-Object) @($before.instances.name | Sort-Object)).Count) {
        throw 'BLOCKED: a successful recent baseline on this package and exact six instances is required.'
    }
    $workspaceId=$w.chaosScenarioId -replace '/scenarios/[^/]+$',''
    $workspace=(Invoke-LabArm Get "https://management.azure.com${workspaceId}?api-version=2026-08-01-preview").body
    $identities=@($workspace.identity.userAssignedIdentities.Values)
    if($identities.Count -ne 1 -or -not $identities[0].principalId) { throw 'BLOCKED: native execution identity is ambiguous.' }
    $nativePrincipal=$identities[0].principalId
    $isDatabase=$TestId -in @('HA-DB-001','HA-COMBINED-001')
    $isApplication=$TestId -ne 'HA-DB-001'
    $applicationDefinition=$null
    $databaseDefinition=$null
    if($isApplication) {
        if(-not $m.outputs.ContainsKey('csl-native-process-scenarios')) { throw 'BLOCKED: validated native process definitions have not been deployed.' }
        $selection=$m.nativeSelection
        $selected=@($before.instances | Where-Object name -eq $selection.instanceId)
        if($selected.Count -ne 1 -or $selected[0].properties.physicalZone -cne $selection.physicalZone) { throw 'BLOCKED: selected native instance/zone placement changed.' }
        $kind=if($TestId -eq 'HA-APP-ZONE-001') { 'zone' } else { 'instance' }
        $outputKey=if($kind -eq 'zone') { 'zoneConfigurationId' } else { 'instanceConfigurationId' }
        $selector=if($kind -eq 'zone') { $selection.logicalZone } else { $selection.instanceId }
        $applicationDefinition=Get-VerifiedNativeDefinition $m.outputs['csl-native-process-scenarios'][$outputKey].value $w.applicationId $kind $selector
        $report.targetInstanceIds=if($kind -eq 'zone') {
            @($before.instances | Where-Object { $_.properties.physicalZone -ceq $selection.physicalZone } | ForEach-Object name)
        } else { @($selection.instanceId) }
        $report.selectedPhysicalZone=$selection.physicalZone
    }
    if($isDatabase) {
        $databaseDefinition=Get-VerifiedNativeDefinition $w.chaosConfigurationId $w.postgresId postgres ''
        if($m.ContainsKey('lastPostgresFaultFinishedAtUtc')) {
            $eligible=([DateTimeOffset]$m.lastPostgresFaultFinishedAtUtc).AddMinutes(20)
            $seconds=[Math]::Ceiling(($eligible-[DateTimeOffset]::UtcNow).TotalSeconds)
            if($seconds -gt 0) {
                Write-Information "Foreground database cooldown: waiting $seconds seconds until $($eligible.ToString('O')); no environment polling." -InformationAction Continue
                Start-Sleep -Seconds $seconds
            }
        }
    }
    $phase=switch($TestId) { 'HA-APP-001' {'app-instance'} 'HA-APP-ZONE-001' {'app-zone'} 'HA-DB-001' {'failover'} 'HA-COMBINED-001' {'combined'} }
    $duration=if($isDatabase) {'18m'} else {'12m'}
    $observerSeconds=if($isDatabase) {1200} else {840}
    $runId=[Guid]::NewGuid().ToString('N')
    $observer=Start-PrivateCommand observer $runId "cd ~/csl && timeout 1500 pwsh -NoLogo -NoProfile -File scripts/runner/observe.ps1 -RunId $runId -Seconds $observerSeconds"
    $measurement=$null
    $results=@()
    $intents=@()
    $dbIntent=$null
    try {
        $measurement=Start-PrivateMeasurement $phase $duration $runId
        Start-Sleep -Seconds 45
        if($measurement.process.HasExited -or $observer.process.HasExited) { throw 'BLOCKED: bounded load or independent observer exited before injection.' }
        & ssh @sshArgs "cd ~/csl && test -s results/$runId/started.json && test -s results/observer-$runId/observations.ndjson"
        if($LASTEXITCODE -ne 0) { throw 'BLOCKED: explicit load and independent observer readiness evidence is missing.' }
        if($isDatabase) {
            $dbIntent=Invoke-SelectedNative $databaseDefinition
            $intents+=@($dbIntent)
            if($TestId -eq 'HA-COMBINED-001') {
                $deadline=[DateTimeOffset]::UtcNow.AddSeconds(180)
                $observed=$false
                do {
                    $lines=& ssh @sshArgs "cd ~/csl && tail -n 4 results/observer-$runId/observations.ndjson"
                    if($LASTEXITCODE -ne 0) { throw 'Independent overlap observer retrieval failed.' }
                    $events=@($lines | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
                    $observed=@($events | Where-Object {
                        $_.kind -eq 'dependencies' -and $_.statusCode -eq 503 -and $_.processId -and
                        $_.dependencyStatus -in @('unavailable','timeout')
                    }).Count -gt 0
                    if(-not $observed) { Start-Sleep -Seconds 2 }
                } while(-not $observed -and [DateTimeOffset]::UtcNow -lt $deadline)
                if(-not $observed) { throw 'INCONCLUSIVE: no independently observed database disruption qualified combined application injection.' }
                $appIntent=Invoke-SelectedNative $applicationDefinition
                $intents+=@($appIntent)
                $results+=@(Complete-SelectedNative $appIntent $applicationDefinition)
            }
            $results+=@(Complete-SelectedNative $dbIntent $databaseDefinition)
        } else {
            $appIntent=Invoke-SelectedNative $applicationDefinition
            $intents+=@($appIntent)
            $results+=@(Complete-SelectedNative $appIntent $applicationDefinition)
        }
    } finally {
        try {
            if($null -ne $dbIntent -and $dbIntent.status -eq 'ACCEPTED') {
                $results+=@(Complete-SelectedNative $dbIntent $databaseDefinition)
            }
        } finally {
            try { Complete-PrivateObserver $observer }
            finally {
                try { if($null -ne $measurement) { $run=Complete-PrivateMeasurement $measurement } }
                finally { Confirm-AllWriteHistory }
            }
        }
    }
    $report.nativeOperations=$intents
    $report.nativeResults=$results
    Invoke-PrivateQualification after | Out-Null
    $afterPostgres=Invoke-LabAz @('postgres','flexible-server','show','-g',$script:LabGroups[1],'-n',$w.postgresName,'-o','json') | ConvertFrom-Json -AsHashtable
    Write-LabJson (Join-Path $caseRoot 'postgres-after.json') $afterPostgres
    $failed=@($results | Where-Object { $_.properties.status -ne 'Succeeded' })
    if($failed.Count) { throw "BLOCKED: native runtime execution failed: $($failed.properties.errors | ConvertTo-Json -Depth 20 -Compress). Exact provider results are retained." }
    $observerPath=Join-Path $stateRoot "evidence\results\observer-$runId\observations.ndjson"
    $attemptsPath=Join-Path $stateRoot "evidence\results\$runId\attempts.ndjson"
    $parameters=@{
        AttemptsPath=$attemptsPath;ObserverPath=$observerPath;CaseRoot=$caseRoot;TestId=$TestId
        SubmittedAtUtc=$intents[0].requestedAtUtc;BeforeInstances=$before.instances;BeforeObservations=$before.observations
        TargetInstanceIds=if($isApplication) {$report.targetInstanceIds} else {@()}
        PostgresBefore=$postgres;PostgresAfter=$afterPostgres
    }
    & (Join-Path $script:LabRoot 'tests\load\evaluate-native.ps1') @parameters
    $effect=Get-Content (Join-Path $caseRoot 'effect-verdict.json') -Raw | ConvertFrom-Json
    $report.effect=$effect
    $report.fullPhase=$run
    $report.status=$effect.status
    $report.reason=$effect.reason
}
function Complete-PrivateMeasurement([hashtable]$Measurement) {
    try {
        if(-not $Measurement.process.WaitForExit(1830000)) {
            Stop-Process -Id $Measurement.process.Id -Force
            throw 'Private measurement exceeded its bounded foreground deadline; guest timeout remains enforced.'
        }
        $Measurement.exitCode=$Measurement.process.ExitCode
        $Measurement.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        $Measurement.stdout.GetAwaiter().GetResult() | Set-Content (Join-Path $caseRoot "$($Measurement.phase)-ssh.stdout.log")
        $Measurement.stderr.GetAwaiter().GetResult() | Set-Content (Join-Path $caseRoot "$($Measurement.phase)-ssh.stderr.log")
        Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase $Measurement.phase -TunnelPort $TunnelPort
        $path=Join-Path $stateRoot "evidence\results\$($Measurement.runId)\run.json"
        if(-not (Test-Path -LiteralPath $path)) { throw "Private measurement produced no run report; inspect guest $($Measurement.phase)-$($Measurement.runId).log." }
        $run=Get-Content $path -Raw | ConvertFrom-Json
        if($run.runId -ne $Measurement.runId -or $run.phase -ne $Measurement.phase) { throw 'Private measurement run attribution differs from its explicit PC request.' }
        Test-LabDurability -ManifestPath $ManifestPath -RunId $Measurement.runId -TunnelPort $TunnelPort -Phase $Measurement.phase
        Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase $Measurement.phase -TunnelPort $TunnelPort
        $report.phases+=@($run)
        return $run
    } finally { $Measurement.process.Dispose() }
}
try {
    if($TestId -eq 'HA-AZ-001') {
        $report.status='BLOCKED'
        $report.reason='A native discrete process crash does not establish a sustained real-zone outage; no qualifying correlated infrastructure-zone evidence exists.'
        return
    }
    if($m.architecture -ne 'linux-app-service') { throw 'BLOCKED: this manifest is not the selected Linux App Service architecture.' }
    Assert-LabPolicyExemptions $m
    if($m.ContainsKey('activeNativeOperations') -and @($m.activeNativeOperations | Where-Object { $_.status -notin @('SUCCEEDED','FAILED_RECONCILED') }).Count) {
        throw 'BLOCKED: reconcile the previously accepted or uncertain native operation before starting another test.'
    }
    $w=$m.outputs['csl-infrastructure'].workload.value
    $postgres=Invoke-LabAz @('postgres','flexible-server','show','-g',$script:LabGroups[1],'-n',$w.postgresName,'-o','json') | ConvertFrom-Json -AsHashtable
    Write-LabJson (Join-Path $caseRoot 'postgres-before.json') $postgres
    if($postgres.state -ne 'Ready' -or $postgres.highAvailability.mode -ne 'ZoneRedundant' -or
        $postgres.highAvailability.state -ne 'Healthy' -or $postgres.network.publicNetworkAccess -ne 'Disabled') {
        throw "BLOCKED: PostgreSQL state=$($postgres.state), HA state=$($postgres.highAvailability.state); require private Ready/Healthy zone-redundant primary/standby before measurement or injection."
    }
    $plan=Invoke-LabAz @('rest','--method','get','--url',
        "https://management.azure.com$($w.applicationId -replace '/sites/[^/]+$','/serverfarms/asp-csl-linux-baseline')?api-version=2025-03-01",'-o','json') | ConvertFrom-Json -AsHashtable
    Write-LabJson (Join-Path $caseRoot 'actual-plan.json') $plan
    Assert-LabAppServicePlan $plan
    $configuration=(Invoke-LabArm GET "https://management.azure.com$($w.applicationId)/config/web?api-version=2025-03-01").body
    Write-LabJson (Join-Path $caseRoot 'actual-app-configuration.json') $configuration
    Assert-LabAppServiceConfiguration $configuration.properties
    Wait-LabSsh $m $stateRoot $TunnelPort
    # Keep CLI tunnel session cleanup outside concurrent measurements and evidence collection.
    $managementSession=Start-PrivateCommand management $caseId 'timeout 7200 cat > /dev/null'
    Start-Sleep -Seconds 3
    if($managementSession.process.HasExited) { throw 'BLOCKED: persistent private management session exited before qualification.' }
    $report.testTooling=Sync-LabTestTooling -ManifestPath $ManifestPath -TunnelPort $TunnelPort
    $report.loadScriptSha256=@($report.testTooling.files | Where-Object path -eq 'tests/load/scenario.js')[0].sha256
    $before=Invoke-PrivateQualification before
    $report.physicalZones=@($before.instances.properties.physicalZone | Sort-Object -Unique)
    foreach($hostName in @($w.applicationFqdn,$w.scmFqdn)) {
        $response=Invoke-WebRequest "https://$hostName/" -TimeoutSec 20 -SkipHttpErrorCheck
        Write-LabJson (Join-Path $caseRoot "$hostName-public-denial.json") @{
            host=$hostName;observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');statusCode=$response.StatusCode
        }
        if($response.StatusCode -ne 403) { throw 'BLOCKED: public application/SCM access was not explicitly denied with HTTP 403.' }
    }
    if($TestId -ne 'BASE-001') { Invoke-NativeCase; return }
    foreach($phase in @(@{name='warmup';duration='5m'},@{name='baseline';duration='10m'})) {
        $runId=[Guid]::NewGuid().ToString('N')
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Starting explicit $($phase.name), $($phase.duration), 20 business operations/second plus one-second canary, run $runId." -InformationAction Continue
        $run=Complete-PrivateMeasurement (Start-PrivateMeasurement $phase.name $phase.duration $runId)
        if($run.status -ne 'PASS') { throw "Private $($phase.name) acceptance failed; original evidence and write reconciliation were retained." }
    }
    Invoke-PrivateQualification after | Out-Null
    $report.status='PASS'
    $report.reason='Five-minute warmup and ten-minute baseline passed, every issued write was reconciled, and all six application instances contributed health/business traffic across three physical zones before and after measurement.'
    $m.lastBaseline=@{status='PASS';completedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');caseRoot=$caseRoot
        packageSha256=$m.applicationPackageSha256;instanceIds=@($before.instances.name)}
    Write-LabJson $ManifestPath $m
} catch {
    $report.status=if($_.Exception.Message -like 'BLOCKED:*') { 'BLOCKED' } elseif($_.Exception.Message -like 'INCONCLUSIVE:*') { 'INCONCLUSIVE' } else { 'FAIL' }
    $report.reason=$_.Exception.Message
    throw
} finally {
    $report.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
    $report.elapsedSeconds=([DateTimeOffset]::UtcNow-$started).TotalSeconds
    Write-LabJson (Join-Path $caseRoot 'verdict.json') $report
    if($null -ne $managementSession) {
        try {
            $managementSession.process.StandardInput.Close()
            if(-not $managementSession.process.WaitForExit(10000)) {
                Stop-Process -Id $managementSession.process.Id -Force
                Write-Warning 'Private management-session client required bounded termination; the guest has a two-hour hard timeout.'
            }
            $managementSession.stderr.GetAwaiter().GetResult() | Set-Content (Join-Path $caseRoot 'management-session.stderr.log')
        } finally { $managementSession.process.Dispose() }
    }
    $lock.Dispose()
    Write-Information "$TestId verdict $($report.status); evidence $caseRoot. No Azure resource cleanup occurred." -InformationAction Continue
}
