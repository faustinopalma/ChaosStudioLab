[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [ValidateSet('BASE-001','HA-NODE-001','HA-ZONE-COMPUTE-001','HA-DB-001','HA-COMBINED-001','HA-AZ-001')][string] $TestId='BASE-001',
    [ValidateRange(1,65535)][int] $TunnelPort=50222
)
. "$PSScriptRoot\Lab.Aks.ps1"
. "$PSScriptRoot\Lab.Aks.Native.ps1"
Confirm-LabContext
$ManifestPath=[IO.Path]::GetFullPath($ManifestPath)
$m=Read-LabManifest $ManifestPath
$root=Split-Path $ManifestPath -Parent
$caseId=[Guid]::NewGuid().ToString('N')
$caseRoot="$root\tests\$TestId-$caseId"
New-Item -ItemType Directory $caseRoot -Force|Out-Null
$started=[DateTimeOffset]::UtcNow
$report=@{schemaVersion=1;testId=$TestId;caseId=$caseId;status='INCONCLUSIVE';reason=$null;phases=@();nativeOperations=@();automaticAzureCleanup=$false;retentionReconciliationSeconds=0;startedAtUtc=$started.ToString('O')}
$lock=[IO.File]::Open("$ManifestPath.lock",'OpenOrCreate','ReadWrite','None')
$sshOptions=@(Get-LabSshOptions $m $root)
$sshArgs=$sshOptions+@('-p',"$TunnelPort",'csloperator@127.0.0.1')
$children=[Collections.Generic.List[hashtable]]::new()
$management=$null
function Invoke-Private([string] $Command){
    & ssh @sshArgs $Command | Out-Host
    if($LASTEXITCODE -ne 0){throw "Private command failed ($LASTEXITCODE): $Command"}
}
function Start-Private([string] $Label,[string] $Command,[string] $ReadyLine){
    $info=[Diagnostics.ProcessStartInfo]::new((Get-Command ssh).Source)
    foreach($arg in $sshArgs){$info.ArgumentList.Add($arg)}
    $info.ArgumentList.Add($Command)
    $info.UseShellExecute=$false
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.RedirectStandardInput=$true
    $p=[Diagnostics.Process]::new();$p.StartInfo=$info
    if(-not $p.Start()){throw 'Private bounded stage failed to start.'}
    $stderr=$p.StandardError.ReadToEndAsync()
    $child=@{label=$Label;process=$p;stderr=$stderr;stdout=$null;completed=$false}
    $children.Add($child)
    if($ReadyLine){
        $line=$p.StandardOutput.ReadLineAsync()
        if(-not $line.Wait(90000) -or $line.GetAwaiter().GetResult() -cne $ReadyLine){
            throw "Private $Label observer did not emit its authenticated readiness marker."
        }
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
function Qualify([string] $Label){
    $name="aks-placement-$caseId-$Label.json"
    Invoke-Private "cd ~/csl && timeout 330 pwsh -NoProfile -File scripts/runner/qualify-aks.ps1 -OutputPath results/$name"
    & scp @sshOptions -P $TunnelPort "csloperator@127.0.0.1:csl/results/$name" "$caseRoot\$name"
    if($LASTEXITCODE -ne 0){throw 'Private placement evidence retrieval failed.'}
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
    $retentionStarted=[DateTimeOffset]::UtcNow
    Invoke-Private "cd ~/csl && timeout 3600 pwsh -NoProfile -File scripts/runner/verify.ps1 -VerifyAllRuns > all-history-$caseId.log 2>&1"
    Save-LabRunnerEvidence $ManifestPath $Phase $TunnelPort
    $history=Get-Content "$root\evidence\results\all-runs-durability.json" -Raw|ConvertFrom-Json -AsHashtable
    if($history.status -ne 'PASS' -or $history.readSource -ne 'private-postgresql-direct-snapshot' -or
        @($history.runs|Where-Object {$_.status -ne 'PASS' -or $_.lostAcknowledgedWrites -ne 0 -or
            $_.readSource -ne 'private-postgresql-direct-snapshot' -or $_.sqlSnapshotSha256 -notmatch '^[0-9a-f]{64}$'}).Count){
        throw 'Every issued/acknowledged write has not been successfully reconciled.'
    }
    $run=Get-Content "$root\evidence\results\$RunId\run.json" -Raw|ConvertFrom-Json -AsHashtable
    $report.phases+=@($run)
    $report.retention=$history
    $report.retentionReconciliationSeconds+=([DateTimeOffset]::UtcNow-$retentionStarted).TotalSeconds
    $report.loadExitCode=$exit
    return $run
}
function Get-Definition([string] $Name,[string] $Kind,[string[]] $Targets){
    $binding=@($m.outputs.native.configurations.value|Where-Object name -eq $Name)
    if($binding.Count -ne 1){throw 'Native configuration output is missing or ambiguous.'}
    $configuration=(Invoke-LabArm Get "https://management.azure.com$($binding[0].id)?api-version=2026-08-01-preview").body
    $scenario=(Invoke-LabArm Get "https://management.azure.com$(Get-LabNativeScenarioId $configuration)?api-version=2026-08-01-preview").body
    Assert-AksNativeDefinition $configuration $scenario $Targets $Kind
    Write-LabJson "$caseRoot\$Kind-definition.json" @{configuration=$configuration;scenario=$scenario}
    return @{configuration=$configuration;scenario=$scenario;kind=$Kind;targets=$Targets}
}
try{
    if($TestId -eq 'HA-AZ-001'){
        $report.status='BLOCKED'
        $report.reason='The AKS compute-zone shutdown affects selected tenant node VMs. No physical Azure-zone disaster encompassing managed control plane, networking, storage and other zonal platform services was injected.'
        throw "BLOCKED: $($report.reason)"
    }
    Assert-LabPolicyExemptions $m
    if($m.ContainsKey('activeNativeOperations') -and @($m.activeNativeOperations|Where-Object {$_.status -notin @('SUCCEEDED','FAILED_RECONCILED')}).Count){
        throw 'BLOCKED: previous accepted/uncertain native execution requires in-place reconciliation.'
    }
    $w=$m.outputs.infrastructure.workload.value
    $beforePg=Get-Postgres before
    Wait-LabSsh $m $root $TunnelPort
    $management=Start-Private management 'timeout 7200 cat > /dev/null' ''
    Start-Sleep 3
    if($management.process.HasExited){throw 'Persistent management session exited.'}
    $report.testTooling=Sync-LabTestTooling $ManifestPath $TunnelPort
    $report.before=Qualify before
    $location=@(Get-Content "$root\physical-zone-mapping.json" -Raw|ConvertFrom-Json -AsHashtable)[0]
    $physical=@(foreach($placement in $report.before.placement){
        $logical=($placement.zone -split '-')[-1]
        $mapping=@($location.availabilityZoneMappings|Where-Object logicalZone -eq $logical)
        if($mapping.Count -ne 1){throw 'Actual worker zone lacks an unambiguous subscription physical-zone mapping.'}
        $mapping[0].physicalZone
    })
    $physical=@($physical|Sort-Object -Unique)
    if($physical.Count -ne 3){throw 'Require actual traffic participants in three observed physical availability zones.'}
    $report.physicalZones=$physical
    if($TestId -eq 'BASE-001'){
        foreach($phase in @(@{name='warmup';duration='5m'},@{name='baseline';duration='10m'})){
            $runId=[Guid]::NewGuid().ToString('N')
            Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] $TestId $($phase.name) $($phase.duration), bounded 20 business ops/s plus one canary/s, run $runId." -InformationAction Continue
            $load=Start-Private "load-$runId" "cd ~/csl && timeout 1800 pwsh -NoProfile -File scripts/runner/test.ps1 -Phase $($phase.name) -Duration $($phase.duration) -RunId $runId > load-$runId.log 2>&1" ''
            $run=Complete-Measurement $load $runId $phase.name
            if($run.status -ne 'PASS'){throw "Baseline $($phase.name) full-phase availability/latency failed; durability evidence retained."}
        }
        $report.after=Qualify after
        $report.status='PASS';$report.reason='Warmup and baseline passed with six private workers across three observed zones, complete traffic participation and zero lost/checksum-mismatched acknowledged writes.'
        $m.lastBaseline=@{status='PASS';completedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');caseRoot=$caseRoot;imageDigest=$m.applicationImageDigest}
        Write-LabJson $ManifestPath $m
    }else{
        $database=$TestId -in @('HA-DB-001','HA-COMBINED-001')
        $compute=$TestId -ne 'HA-DB-001'
        $definitions=@()
        if($compute){
            $kind=if($TestId -eq 'HA-NODE-001'){'node'}else{'zone'}
            $targets=if($kind -eq 'node'){@($m.nativeTargets.single)}else{@($m.nativeTargets.zone)}
            $name=if($kind -eq 'node'){'aks-exact-node-shutdown'}else{'aks-selected-zone-shutdown'}
            $computeDefinition=Get-Definition $name $kind $targets
            $definitions+=@($computeDefinition)
        }
        if($database){
            $dbDefinition=Get-Definition 'aks-postgres-forced-failover' database @($w.postgresId)
            $definitions+=@($dbDefinition)
            if($m.ContainsKey('lastPostgresFaultFinishedAtUtc')){
                $wait=[Math]::Ceiling((([DateTimeOffset]$m.lastPostgresFaultFinishedAtUtc).AddMinutes(20)-[DateTimeOffset]::UtcNow).TotalSeconds)
                if($wait -gt 0){Write-Information "Foreground database eligibility cooldown $wait seconds; no environment polling." -InformationAction Continue;Start-Sleep -Seconds $wait}
            }
        }
        $workspace=$m.outputs.native.workspaceId.value
        New-Item -ItemType Directory "$caseRoot\discovery"|Out-Null
        Find-LabNativeTargets $workspace @($definitions|ForEach-Object {$_.targets}) "$caseRoot\discovery" @($m.groups[1].id,$m.groups[3].id)|Out-Null
        foreach($definition in $definitions){
            Confirm-AksNativeValidation $definition.configuration.id $definition.targets "$caseRoot\$($definition.kind)-validation"|Out-Null
        }
        $phase=switch($TestId){'HA-NODE-001'{'app-instance'}'HA-ZONE-COMPUTE-001'{'app-zone'}'HA-DB-001'{'failover'}'HA-COMBINED-001'{'combined'}}
        $duration='18m'
        $seconds=1200
        $runId=[Guid]::NewGuid().ToString('N')
        $health=Start-Private health "cd ~/csl && timeout 1500 pwsh -NoProfile -File scripts/runner/observe.ps1 -RunId $runId -Seconds $seconds" "OBSERVER_READY:$runId"
        $topology=Start-Private topology "cd ~/csl && timeout 1500 pwsh -NoProfile -File scripts/runner/observe-aks.ps1 -RunId $runId -Seconds $seconds" "TOPOLOGY_READY:$runId"
        $first=& ssh @sshArgs "cd ~/csl && head -n 1 results/topology-$runId/observations.ndjson"
        if($LASTEXITCODE -ne 0){throw 'Initial topology observation retrieval failed.'}
        $initial=$first|ConvertFrom-Json -AsHashtable
        $targetVms=@(if($compute){$initial.vms|Where-Object {$_.scaleSetId -in $computeDefinition.targets -and
            ($computeDefinition.kind -eq 'node' -or '1' -in $_.zones)}|ForEach-Object id})
        if($compute -and $targetVms.Count -ne $(if($TestId -eq 'HA-NODE-001'){1}else{3})){throw 'Actual native selector does not cover the intended exact VM set.'}
        $report.targetVmIds=$targetVms
        if($compute){$computeDefinition.targetVmIds=$targetVms}
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] $TestId $duration bounded load run $runId; independent power/topology and dependency observers ready." -InformationAction Continue
        $load=Start-Private "load-$runId" "cd ~/csl && timeout 1800 pwsh -NoProfile -File scripts/runner/test.ps1 -Phase $phase -Duration $duration -RunId $runId > load-$runId.log 2>&1" ''
        $intents=@();$results=@();$nativeError=$null
        try{
            Start-Sleep 45
            if($load.process.HasExited -or $health.process.HasExited -or $topology.process.HasExited){throw 'BLOCKED: load/observer ended before injection.'}
            Invoke-Private "cd ~/csl && test -s results/$runId/started.json"
            if($database){
                $dbIntent=Start-LabNativeExecution $dbDefinition.configuration.id $m $ManifestPath "$caseRoot\database"
                $intents+=@(@{intent=$dbIntent;definition=$dbDefinition})
                if($compute){
                    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(360);$bad=$false
                    do{
                        $lines=& ssh @sshArgs "cd ~/csl && tail -n 4 results/observer-$runId/observations.ndjson"
                        if($LASTEXITCODE -ne 0){throw 'Independent combined-trigger observation retrieval failed.'}
                        $bad=@($lines|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json -AsHashtable}|Where-Object {
                            $_.kind -eq 'dependencies' -and $_.statusCode -eq 503 -and $_.processId -and
                            $_.dependencyStatus -in @('timeout','unavailable') -and [DateTimeOffset]$_.requestedAtUtc -ge [DateTimeOffset]$dbIntent.requestedAtUtc
                        }).Count -gt 0
                        if(-not $bad){Start-Sleep 2}
                    }while(-not $bad -and [DateTimeOffset]::UtcNow -lt $deadline)
                    if(-not $bad){throw 'INCONCLUSIVE: independent database disruption did not qualify combined compute injection.'}
                }
            }
            if($compute){
                $computeIntent=Start-LabNativeExecution $computeDefinition.configuration.id $m $ManifestPath "$caseRoot\compute"
                $intents+=@(@{intent=$computeIntent;definition=$computeDefinition})
            }
        }catch{$nativeError=$_.Exception.Message;Write-Warning $nativeError}
        finally{
            foreach($entry in $intents){
                try{$results+=@(Complete-AksNativeExecution $entry.intent $entry.definition $m $ManifestPath "$caseRoot\$($entry.definition.kind)")}
                catch{$nativeError=$_.Exception.Message;Write-Warning $nativeError}
            }
            $report.nativeOperations=@($intents|ForEach-Object intent);$report.nativeResults=$results
            $report.observerExitCodes=@{health=(Complete-Private $health);topology=(Complete-Private $topology)}
            $run=Complete-Measurement $load $runId $phase
            if($report.observerExitCodes.health -ne 0 -or $report.observerExitCodes.topology -ne 0){
                throw 'INCONCLUSIVE: independent observer failed; completed load, explicit observer logs and full retention evidence are preserved.'
            }
        }
        $report.nativeOperations=@($intents|ForEach-Object intent);$report.nativeResults=$results;$report.fullPhase=$run
        $afterPg=Get-Postgres after
        if($nativeError){throw "BLOCKED: $nativeError"}
        & "$script:LabRoot\tests\load\evaluate-aks.ps1" `
            -AttemptsPath "$root\evidence\results\$runId\attempts.ndjson" -TopologyPath "$root\evidence\results\topology-$runId\observations.ndjson" `
            -ObserverPath "$root\evidence\results\observer-$runId\observations.ndjson" -CaseRoot $caseRoot -TestId $TestId `
            -SubmittedAtUtc $intents[0].intent.requestedAtUtc -TargetVmIds $targetVms -PostgresBefore $beforePg -PostgresAfter $afterPg
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
    throw
}finally{
    foreach($child in $children){
        if($child -eq $management){$child.process.StandardInput.Close()}
        if(-not $child.completed){
            try{Complete-Private $child $(if($child -eq $management){10}else{1830})|Out-Null}
            catch{Write-Warning "Stage reconciliation: $($_.Exception.Message)"}
        }
        $child.process.Dispose()
    }
    $report.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');$report.elapsedSeconds=([DateTimeOffset]::UtcNow-$started).TotalSeconds
    Write-LabJson "$caseRoot\verdict.json" $report
    $lock.Dispose()
    Write-Information "$TestId $($report.status), evidence $caseRoot; no Azure lab teardown." -InformationAction Continue
}
if($report.status -ne 'PASS'){exit 1}
