[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [ValidateSet('BASE-001','HA-REPLICA-001','HA-DB-001','HA-COMBINED-001','HA-AZ-001')][string] $TestId='BASE-001',
    [ValidateRange(1,65535)][int] $TunnelPort=40222
)
. "$PSScriptRoot\Lab.Aca.ps1"
. "$PSScriptRoot\Lab.Aks.Native.ps1"
Confirm-LabContext
$ManifestPath=[IO.Path]::GetFullPath($ManifestPath)
$m=Read-LabManifest $ManifestPath
$root=Split-Path $ManifestPath -Parent
$caseId=[Guid]::NewGuid().ToString('N')
$caseRoot="$root\tests\$TestId-$caseId"
New-Item -ItemType Directory $caseRoot -Force|Out-Null
$started=[DateTimeOffset]::UtcNow
$report=@{schemaVersion=1;testId=$TestId;caseId=$caseId;status='INCONCLUSIVE';reason=$null;phases=@();nativeOperations=@();retentionReconciliationSeconds=0;startedAtUtc=$started.ToString('O')}
$lock=[IO.File]::Open("$ManifestPath.lock",'OpenOrCreate','ReadWrite','None')
$sshOptions=@(Get-LabSshOptions $m $root)
$sshArgs=$sshOptions+@('-p',"$TunnelPort",'csloperator@127.0.0.1')
$children=[Collections.Generic.List[hashtable]]::new()
function Invoke-Private([string] $Command,[switch] $Retry){
    for($attempt=1;;$attempt++){
        & ssh @sshArgs $Command | Out-Host
        $exit=$LASTEXITCODE
        if($exit -eq 0){return}
        # ssh returns 255 for its own transport failures; only idempotent commands are retried after the tunnel recovers.
        if(-not $Retry -or $exit -ne 255 -or $attempt -ge 4){throw "Private command failed ($exit): $Command"}
        Write-Warning "Private transport failed ($attempt/3); waiting for the tunnel and retrying the idempotent command."
        Start-Sleep 15
        Wait-LabSsh $m $root $TunnelPort
    }
}
function Start-Private([string] $Label,[string] $Command,[string] $ReadyLine){
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command ssh).Source)
    foreach($arg in $sshArgs){$info.ArgumentList.Add($arg)}
    $info.ArgumentList.Add($Command)
    $info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.RedirectStandardInput=$true
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info
    if(-not $p.Start()){throw 'Private bounded stage failed to start.'}
    $stderr=$p.StandardError.ReadToEndAsync()
    $child=@{label=$Label;process=$p;stderr=$stderr;stdout=$null;completed=$false}
    $children.Add($child)
    if($ReadyLine){
        $line=$p.StandardOutput.ReadLineAsync()
        if(-not $line.Wait(90000) -or $line.GetAwaiter().GetResult() -cne $ReadyLine){throw "Private $Label observer did not emit its readiness marker."}
    }
    $child.stdout=$p.StandardOutput.ReadToEndAsync()
    return $child
}
function Complete-Private([hashtable] $Child,[int] $TimeoutSeconds=1830){
    if($Child.completed){return $Child.exitCode}
    if(-not $Child.process.WaitForExit($TimeoutSeconds*1000)){
        Stop-Process -Id $Child.process.Id -Force
        throw "Bounded $($Child.label) exceeded its deadline; guest timeout remains enforced."
    }
    $Child.exitCode=$Child.process.ExitCode;$Child.completed=$true
    if($null -ne $Child.stdout){$Child.stdout.GetAwaiter().GetResult()|Set-Content "$caseRoot\$($Child.label).stdout.log"}
    $Child.stderr.GetAwaiter().GetResult()|Set-Content "$caseRoot\$($Child.label).stderr.log"
    return $Child.exitCode
}
function Get-Remote([string] $Remote,[string] $Local){
    for($attempt=1;$attempt -le 4;$attempt++){
        & scp @sshOptions -P $TunnelPort "csloperator@127.0.0.1:$Remote" $Local
        if($LASTEXITCODE -eq 0){return}
        Start-Sleep 15
    }
    throw "Private evidence retrieval failed: $Remote"
}
function Qualify([string] $Label){
    $name="aca-placement-$caseId-$Label.json"
    Invoke-Private "cd ~/csl && timeout 330 pwsh -NoProfile -File scripts/runner/qualify-aca.ps1 -OutputPath results/$name" -Retry
    Get-Remote "csl/results/$name" "$caseRoot\$name"
    Get-Content "$caseRoot\$name" -Raw|ConvertFrom-Json -AsHashtable
}
function Get-Postgres([string] $Label){
    $pg=Invoke-LabAz @('postgres','flexible-server','show','-g',$script:LabGroups[1],'-n',$w.postgresName,'-o','json')|ConvertFrom-Json -AsHashtable
    Write-LabJson "$caseRoot\postgres-$Label.json" $pg
    if($pg.state -ne 'Ready' -or $pg.highAvailability.mode -ne 'ZoneRedundant' -or $pg.highAvailability.state -ne 'Healthy' -or
        $pg.network.publicNetworkAccess -ne 'Disabled'){throw 'BLOCKED: actual database must be private, Ready and Healthy zone-redundant HA.'}
    return $pg
}
function Complete-Measurement([hashtable] $Load,[string] $RunId,[string] $Phase){
    $exit=Complete-Private $Load
    if($exit -eq 255){
        # The SSH session dropped; the guest load keeps writing to its own log. Wait for its own completion record.
        Write-Warning 'Load session transport dropped; waiting for the guest run to write run.json.'
        $deadline=[DateTimeOffset]::UtcNow.AddMinutes(25)
        do{
            Start-Sleep 30
            & ssh @sshArgs "test -s ~/csl/results/$RunId/run.json" 2>$null
            $done=$LASTEXITCODE -eq 0
        }while(-not $done -and [DateTimeOffset]::UtcNow -lt $deadline)
        if(-not $done){throw "Guest load $RunId did not complete after the transport drop."}
        $exit=0
    }
    $retentionStarted=[DateTimeOffset]::UtcNow
    Invoke-Private "cd ~/csl && timeout 3600 pwsh -NoProfile -File scripts/runner/verify.ps1 -VerifyAllRuns > all-history-$caseId.log 2>&1" -Retry
    Save-LabRunnerEvidence $ManifestPath $Phase $TunnelPort
    $history=Get-Content "$root\evidence\results\all-runs-durability.json" -Raw|ConvertFrom-Json -AsHashtable
    if($history.status -ne 'PASS' -or $history.readSource -ne 'private-postgresql-direct-snapshot' -or
        @($history.runs|Where-Object {$_.status -ne 'PASS' -or $_.lostAcknowledgedWrites -ne 0 -or $_.readSource -ne 'private-postgresql-direct-snapshot'}).Count){
        throw 'Every issued/acknowledged write has not been successfully reconciled against direct PostgreSQL.'
    }
    $run=Get-Content "$root\evidence\results\$RunId\run.json" -Raw|ConvertFrom-Json -AsHashtable
    $report.phases+=@($run)
    $report.retention=$history
    $report.retentionReconciliationSeconds+=([DateTimeOffset]::UtcNow-$retentionStarted).TotalSeconds
    $report.loadExitCode=$exit
    return $run
}
try{
    if($TestId -eq 'HA-AZ-001'){
        $report.status='BLOCKED'
        $report.reason='Container Apps exposes no replica zone and Chaos Studio has no Container Apps or managed-environment fault. No physical Azure-zone disaster was injected.'
        throw "BLOCKED: $($report.reason)"
    }
    Assert-LabPolicyExemptions $m
    if(@($m.activeNativeOperations|Where-Object {$_.status -notin @('SUCCEEDED','FAILED_RECONCILED')}).Count){
        throw 'BLOCKED: previous accepted/uncertain native execution requires in-place reconciliation.'
    }
    $w=$m.outputs.infrastructure.workload.value
    $beforePg=Get-Postgres before
    Wait-LabSsh $m $root $TunnelPort
    $report.testTooling=Sync-LabTestTooling $ManifestPath $TunnelPort
    $report.before=Qualify before
    if($TestId -eq 'BASE-001'){
        foreach($phase in @(@{name='warmup';duration='5m'},@{name='baseline';duration='10m'})){
            $runId=[Guid]::NewGuid().ToString('N')
            Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] $TestId $($phase.name) $($phase.duration), 20 business ops/s plus one canary/s, run $runId." -InformationAction Continue
            $load=Start-Private "load-$runId" "cd ~/csl && timeout 1800 pwsh -NoProfile -File scripts/runner/test.ps1 -Phase $($phase.name) -Duration $($phase.duration) -RunId $runId > load-$runId.log 2>&1" ''
            $run=Complete-Measurement $load $runId $phase.name
            if($run.status -ne 'PASS'){throw "Baseline $($phase.name) full-phase availability/latency failed; durability evidence retained."}
        }
        $report.after=Qualify after
        $report.status='PASS';$report.reason='Warmup and baseline passed with six private replicas, complete participation and zero lost/checksum-mismatched acknowledged writes.'
        $m.lastBaseline=@{status='PASS';completedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');caseRoot=$caseRoot;imageDigest=$m.applicationImageDigest}
        Write-LabJson $ManifestPath $m
    }else{
        if(-not $m.ContainsKey('lastBaseline') -or $m.lastBaseline.status -ne 'PASS' -or $m.lastBaseline.imageDigest -ne $m.applicationImageDigest){
            throw 'BLOCKED: a passing baseline on the deployed image is required before fault injection.'
        }
        $database=$TestId -ne 'HA-REPLICA-001'
        $replicaFault=$TestId -ne 'HA-DB-001'
        if($database){
            $binding=@($m.outputs.native.configurations.value|Where-Object name -eq 'aca-postgres-forced-failover')
            if($binding.Count -ne 1){throw 'Native configuration output is missing or ambiguous.'}
            $configuration=(Invoke-LabArm Get "https://management.azure.com$($binding[0].id)?api-version=2026-08-01-preview").body
            $scenario=(Invoke-LabArm Get "https://management.azure.com$(Get-LabNativeScenarioId $configuration)?api-version=2026-08-01-preview").body
            Assert-AksNativeDefinition $configuration $scenario @($w.postgresId) database
            $dbDefinition=@{configuration=$configuration;scenario=$scenario;kind='database';targets=@($w.postgresId)}
            Write-LabJson "$caseRoot\database-definition.json" $dbDefinition
            if($m.ContainsKey('lastPostgresFaultFinishedAtUtc')){
                $wait=[Math]::Ceiling((([DateTimeOffset]$m.lastPostgresFaultFinishedAtUtc).AddMinutes(20)-[DateTimeOffset]::UtcNow).TotalSeconds)
                if($wait -gt 0){Write-Information "Database eligibility cooldown $wait seconds." -InformationAction Continue;Start-Sleep -Seconds $wait}
            }
            New-Item -ItemType Directory "$caseRoot\discovery"|Out-Null
            Find-LabNativeTargets $m.outputs.native.workspaceId.value @($w.postgresId) "$caseRoot\discovery" @($m.groups[1].id)|Out-Null
            Confirm-AksNativeValidation $configuration.id @($w.postgresId) "$caseRoot\database-validation"|Out-Null
        }
        $phase=switch($TestId){'HA-REPLICA-001'{'app-instance'}'HA-DB-001'{'failover'}'HA-COMBINED-001'{'combined'}}
        $runId=[Guid]::NewGuid().ToString('N')
        $health=Start-Private health "cd ~/csl && timeout 1500 pwsh -NoProfile -File scripts/runner/observe.ps1 -RunId $runId -Seconds 1200" "OBSERVER_READY:$runId"
        $topology=Start-Private topology "cd ~/csl && timeout 1500 pwsh -NoProfile -File scripts/runner/observe-aca.ps1 -RunId $runId -Seconds 1200" "TOPOLOGY_READY:$runId"
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] $TestId 18m load run $runId; independent replica and dependency observers ready." -InformationAction Continue
        $load=Start-Private "load-$runId" "cd ~/csl && timeout 1800 pwsh -NoProfile -File scripts/runner/test.ps1 -Phase $phase -Duration 18m -RunId $runId > load-$runId.log 2>&1" ''
        $intent=$null;$nativeResult=$null;$nativeError=$null;$faultPath=$null;$submittedAt=$null
        try{
            Start-Sleep 45
            if($load.process.HasExited -or $health.process.HasExited -or $topology.process.HasExited){throw 'BLOCKED: load/observer ended before injection.'}
            Invoke-Private "cd ~/csl && test -s results/$runId/started.json" -Retry
            if($database){
                $intent=Start-LabNativeExecution $configuration.id $m $ManifestPath "$caseRoot\database"
                $submittedAt=[DateTimeOffset]$intent.requestedAtUtc
                if($replicaFault){
                    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(360);$bad=$false
                    do{
                        $lines=& ssh @sshArgs "cd ~/csl && tail -n 4 results/observer-$runId/observations.ndjson"
                        if($LASTEXITCODE -ne 0){throw 'Independent combined-trigger observation retrieval failed.'}
                        $bad=@($lines|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json -AsHashtable}|Where-Object {
                            $_.kind -eq 'dependencies' -and $_.statusCode -eq 503 -and $_.processId -and
                            $_.dependencyStatus -in @('timeout','unavailable') -and [DateTimeOffset]$_.requestedAtUtc -ge $submittedAt}).Count -gt 0
                        if(-not $bad){Start-Sleep 2}
                    }while(-not $bad -and [DateTimeOffset]::UtcNow -lt $deadline)
                    if(-not $bad){throw 'INCONCLUSIVE: independent database disruption did not qualify the combined replica withdrawal.'}
                }
            }
            if($replicaFault){
                $name="replica-fault-$runId.json"
                $faultStarted=[DateTimeOffset]::UtcNow
                if(-not $submittedAt){$submittedAt=$faultStarted}
                try{Invoke-Private "cd ~/csl && timeout 120 pwsh -NoProfile -File scripts/runner/fault-aca.ps1 -OutputPath results/$name -Count 2 -TtlSeconds 360 -Mode unready -Reason $TestId"}
                catch{
                    # Never resubmit the fault: wait for the guest adapter's own result after a transport drop.
                    Write-Warning "Fault adapter session failed: $($_.Exception.Message). Waiting for the guest result without resubmitting."
                    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(180);$done=$false
                    do{Start-Sleep 15;& ssh @sshArgs "test -s ~/csl/results/$name" 2>$null;$done=$LASTEXITCODE -eq 0}while(-not $done -and [DateTimeOffset]::UtcNow -lt $deadline)
                    if(-not $done){throw}
                }
                $faultPath="$caseRoot\$name"
                Get-Remote "csl/results/$name" $faultPath
                $report.replicaFault=Get-Content $faultPath -Raw|ConvertFrom-Json -AsHashtable
            }
        }catch{$nativeError=$_.Exception.Message;Write-Warning $nativeError}
        finally{
            if($intent){
                try{$nativeResult=Complete-AksNativeExecution $intent $dbDefinition $m $ManifestPath "$caseRoot\database"}
                catch{$nativeError=$_.Exception.Message;Write-Warning $nativeError}
            }
            $report.nativeOperations=@($intent|Where-Object {$_});$report.nativeResult=$nativeResult
            $report.observerExitCodes=@{health=(Complete-Private $health);topology=(Complete-Private $topology)}
            $run=Complete-Measurement $load $runId $phase
            if($report.observerExitCodes.health -ne 0 -or $report.observerExitCodes.topology -ne 0){
                throw 'INCONCLUSIVE: independent observer failed; completed load, observer logs and full retention evidence are preserved.'
            }
        }
        $report.fullPhase=$run
        $afterPg=Get-Postgres after
        if($nativeError){throw "BLOCKED: $nativeError"}
        $evaluation=@{AttemptsPath="$root\evidence\results\$runId\attempts.ndjson";TopologyPath="$root\evidence\results\topology-$runId\observations.ndjson"
            ObserverPath="$root\evidence\results\observer-$runId\observations.ndjson";CaseRoot=$caseRoot;TestId=$TestId;SubmittedAtUtc=$submittedAt
            PostgresBefore=$beforePg;PostgresAfter=$afterPg}
        if($faultPath){$evaluation.FaultPath=$faultPath}
        & "$script:LabRoot\tests\load\evaluate-aca.ps1" @evaluation
        $report.effect=Get-Content "$caseRoot\effect-verdict.json" -Raw|ConvertFrom-Json -AsHashtable
        $report.status=$report.effect.status;$report.reason=$report.effect.reason
        if($run.status -ne 'PASS'){
            $report.status=if($report.effect.status -eq 'INCONCLUSIVE'){'INCONCLUSIVE'}else{'FAIL'}
            $report.reason="Full-phase availability/latency verdict is $($run.status). $($report.effect.reason)"
        }
        $report.after=Qualify after
    }
}catch{
    $report.status=if($_.Exception.Message -like 'BLOCKED:*'){'BLOCKED'}elseif($_.Exception.Message -like 'INCONCLUSIVE:*'){'INCONCLUSIVE'}else{'FAIL'}
    $report.reason=$_.Exception.Message
    $report.errorStackTrace=$_.ScriptStackTrace
    Write-Warning $report.reason
}finally{
    foreach($child in $children){
        if(-not $child.completed){
            try{Complete-Private $child 1830|Out-Null}catch{Write-Warning "Stage reconciliation: $($_.Exception.Message)"}
        }
        $child.process.Dispose()
    }
    $report.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');$report.elapsedSeconds=([DateTimeOffset]::UtcNow-$started).TotalSeconds
    Write-LabJson "$caseRoot\verdict.json" $report
    $lock.Dispose()
    Write-Information "$TestId $($report.status): $($report.reason)" -InformationAction Continue
    Write-Information "Evidence: $caseRoot" -InformationAction Continue
}
if($report.status -ne 'PASS'){exit 1}
