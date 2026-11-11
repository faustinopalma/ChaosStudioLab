param(
    [Parameter(Mandatory)][string] $AttemptsPath,
    [Parameter(Mandatory)][string] $TopologyPath,
    [Parameter(Mandatory)][string] $ObserverPath,
    [Parameter(Mandatory)][string] $CaseRoot,
    [Parameter(Mandatory)][ValidateSet('HA-REPLICA-001','HA-DB-001','HA-COMBINED-001')][string] $TestId,
    [Parameter(Mandatory)][DateTimeOffset] $SubmittedAtUtc,
    [string] $FaultPath,
    [Parameter(Mandatory)][hashtable] $PostgresBefore,
    [Parameter(Mandatory)][hashtable] $PostgresAfter
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$result=@{status='INCONCLUSIVE';reason='Required independently observed effects are incomplete.';replicas=$null;overlap=$null;recovery=$null;stable=$null}
$failures=[Collections.Generic.List[string]]::new()
function Read-Events([string]$Path){@(Get-Content $Path|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})}
try{
    $events=Read-Events $AttemptsPath
    $topology=Read-Events $TopologyPath
    $observer=Read-Events $ObserverPath
    $replicaFault=$TestId -ne 'HA-DB-001'
    $database=$TestId -ne 'HA-REPLICA-001'
    $effectTime=$null
    if($replicaFault){
        $fault=Get-Content $FaultPath -Raw|ConvertFrom-Json -AsHashtable
        $targets=@($fault.targets|ForEach-Object replicaId)
        if($fault.status -ne 'APPLIED' -or $targets.Count -ne 2){throw 'INCONCLUSIVE: the fault adapter did not withdraw exactly two distinct replicas.'}
        $appliedAt=@($fault.targets|ForEach-Object {[DateTimeOffset]$_.acceptedAtUtc}|Sort-Object)[-1]
        $before=@($topology|Where-Object {[DateTimeOffset]$_.observedAtUtc -le $appliedAt})
        if(-not $before.Count){throw 'INCONCLUSIVE: no replica inventory precedes the fault.'}
        $initial=@($before[-1].replicas)
        $survivors=@($initial|Where-Object {$_.name -notin $targets}|ForEach-Object name)
        if($initial.Count -ne 6 -or $survivors.Count -ne 4 -or @($targets|Where-Object {$_ -notin $initial.name}).Count){
            throw 'INCONCLUSIVE: targets are not two of the six replicas observed immediately before the fault.'
        }
        $firstOff=$null;$lastOff=$null;$qualified=$null
        foreach($sample in $topology){
            if([DateTimeOffset]$sample.requestedAtUtc -lt $appliedAt.AddSeconds(-5)){continue}
            $time=([DateTimeOffset]$sample.observedAtUtc).ToUniversalTime()
            $off=@($sample.replicas|Where-Object {$_.name -in $targets -and $_.ready -eq $false -and $_.runningState -eq 'Running'})
            $healthy=@($sample.replicas|Where-Object {$_.name -in $survivors -and $_.ready -eq $true})
            $unplanned=@($sample.replicas|Where-Object {$_.name -notin $initial.name})
            $valid=$off.Count -eq 2 -and $healthy.Count -eq 4 -and -not $unplanned.Count
            if(-not $valid -or ($null -ne $lastOff -and ($time-$lastOff).TotalSeconds -gt 30)){
                if($null -ne $qualified){break}
                $firstOff=$null;$lastOff=$null
                continue
            }
            if($null -eq $firstOff){$firstOff=$time}
            $lastOff=$time
            if(($lastOff-$firstOff).TotalSeconds -ge 300){
                $qualified=@{startedAtUtc=$firstOff.ToString('O');verifiedThroughUtc=$lastOff.ToString('O');minimumVerifiedSeconds=($lastOff-$firstOff).TotalSeconds
                    targetReplicas=$targets;survivingReplicas=$survivors;faultAppliedAtUtc=$appliedAt.ToString('O');maximumSampleGapSeconds=30}
            }
        }
        if($null -eq $qualified){throw 'INCONCLUSIVE: ARM replica readiness did not show both targets withdrawn and four survivors ready for a continuous >=300 seconds.'}
        $effectTime=[DateTimeOffset]$qualified.startedAtUtc
        $outageEnd=[DateTimeOffset]$qualified.verifiedThroughUtc
        $served=@($events|Where-Object {$_.type -eq 'attempt' -and $_.success -eq $true -and
            [DateTimeOffset]$_.recordedAtUtc -ge $effectTime.AddSeconds(5) -and [DateTimeOffset]$_.recordedAtUtc -le $outageEnd})
        $fromTargets=@($served|Where-Object {$_.instanceId -in $targets})
        $survivorTraffic=@($served|ForEach-Object instanceId|Where-Object {$_ -in $survivors}|Sort-Object -Unique)
        if($fromTargets.Count){throw "INCONCLUSIVE: withdrawn replicas still served $($fromTargets.Count) successful attempts; routing withdrawal is unproven."}
        if($survivorTraffic.Count -lt 3){throw 'INCONCLUSIVE: fewer than three surviving replicas served traffic during the withdrawal.'}
        $qualified.survivorsServingTraffic=$survivorTraffic
        $result.replicas=$qualified
        if(-not $database){
            $windowStart=[DateTimeOffset]::FromUnixTimeSeconds([long][Math]::Ceiling($appliedAt.ToUnixTimeMilliseconds()/1000.0))
            $windowEnd=$windowStart.AddSeconds(300)
            $operations=@($events|Where-Object {$_.type -eq 'businessOperation' -and [DateTimeOffset]$_.startedAtUtc -ge $windowStart -and [DateTimeOffset]$_.startedAtUtc -lt $windowEnd})
            $drops=@($events|Where-Object {$_.type -eq 'droppedScheduledOperation' -and $_.scenario -eq 'workload' -and
                [DateTimeOffset]$_.recordedAtUtc -ge $windowStart -and [DateTimeOffset]$_.recordedAtUtc -lt $windowEnd})
            $dropCount=0.0;foreach($drop in $drops){$dropCount+=[double]$drop.count}
            $ticks=@($events|Where-Object {$_.type -eq 'canaryTick' -and [DateTimeOffset]$_.scheduledAtUtc -ge $windowStart -and [DateTimeOffset]$_.scheduledAtUtc -lt $windowEnd}|Sort-Object scheduledAtUtc)
            if($operations.Count+$dropCount -ne 6000 -or $ticks.Count -ne 300){throw 'INCONCLUSIVE: first five-minute post-fault window lacks complete business/canary sampling.'}
            $success=@($operations|Where-Object success -eq $true)
            $durations=@($success|ForEach-Object {[double]$_.durationMs}|Sort-Object)
            $p95=if($durations.Count){$durations[[Math]::Max(0,[int][Math]::Ceiling(0.95*$durations.Count)-1)]}else{$null}
            $consecutive=0;$longest=0
            foreach($tick in $ticks){if($tick.success){$consecutive=0}else{$consecutive++;$longest=[Math]::Max($longest,$consecutive)}}
            $window=@{startedAtUtc=$windowStart.ToString('O');endedAtUtc=$windowEnd.ToString('O');businessSuccessRate=$success.Count/6000.0;failedOperations=6000-$success.Count
                successfulOperationP95Ms=$p95;droppedOperations=$dropCount;longestCompleteUnavailabilitySeconds=$longest}
            $window.status=if($window.businessSuccessRate -lt 0.99 -or $null -eq $p95 -or $p95 -gt 2000 -or $longest -gt 5){'FAIL'}else{'PASS'}
            if($window.status -eq 'FAIL'){$failures.Add('FAIL: first five-minute replica-withdrawal window exceeded 99% business success, two-second p95 or five-second unavailability limits.')}
            $result.replicas.firstFiveMinutes=$window
            $effectTime=$windowStart
        }
    }
    if($database){
        if($PostgresAfter.state -ne 'Ready' -or $PostgresAfter.highAvailability.mode -ne 'ZoneRedundant' -or $PostgresAfter.highAvailability.state -ne 'Healthy' -or
            $PostgresAfter.availabilityZone -cne $PostgresBefore.highAvailability.standbyAvailabilityZone -or
            $PostgresAfter.highAvailability.standbyAvailabilityZone -cne $PostgresBefore.availabilityZone){
            throw 'INCONCLUSIVE: independently captured PostgreSQL healthy primary/standby zone swap is missing.'
        }
        $dependency=@($observer|Where-Object {$_.kind -eq 'dependencies' -and [DateTimeOffset]$_.requestedAtUtc -ge $SubmittedAtUtc})
        $bad=@($dependency|Where-Object {$_.statusCode -eq 503 -and $_.processId -and $_.dependencyStatus -in @('timeout','unavailable')})
        if(-not $bad.Count){throw 'INCONCLUSIVE: no independently observed database disruption bounds recovery.'}
        if($replicaFault){
            $withdrawn=$appliedAt
            $left=@($bad|Where-Object {[DateTimeOffset]$_.observedAtUtc -le $withdrawn}|Select-Object -Last 1)
            $right=@($bad|Where-Object {[DateTimeOffset]$_.requestedAtUtc -ge $withdrawn -and [DateTimeOffset]$_.observedAtUtc -le $outageEnd}|Select-Object -First 1)
            if($left.Count -ne 1 -or $right.Count -ne 1 -or @($dependency|Where-Object {$_.statusCode -eq 200 -and
                [DateTimeOffset]$_.requestedAtUtc -ge [DateTimeOffset]$left[0].observedAtUtc -and [DateTimeOffset]$_.observedAtUtc -le [DateTimeOffset]$right[0].requestedAtUtc}).Count){
                throw 'INCONCLUSIVE: independently observed database failures do not bracket the replica withdrawal.'
            }
            $result.overlap=@{status='PASS';databaseFailureBefore=$left[0];replicaWithdrawalAtUtc=$withdrawn.ToString('O');databaseFailureAfter=$right[0]}
        }
        $effectTime=([DateTimeOffset]$bad[0].observedAtUtc).ToUniversalTime()
    }
    $evidencePath=Join-Path $CaseRoot 'independent-effect.json'
    $noInterruption=$false
    if(-not $database){
        $near=@($observer|Where-Object {[DateTimeOffset]$_.requestedAtUtc -ge $effectTime.AddSeconds(-10) -and [DateTimeOffset]$_.observedAtUtc -le $effectTime.AddSeconds(60)})
        $noInterruption=@($near|Where-Object kind -eq live).Count -ge 10 -and @($near|Where-Object kind -eq dependencies).Count -ge 10 -and -not @($near|Where-Object {$_.statusCode -ne 200}).Count
    }
    @{schemaVersion=1;source='private ARM replica readiness observer, private dependency probes and PostgreSQL primary/standby inventory'
        targetResourceId=if($database){$PostgresBefore.id}else{"replicas:$($targets -join ',')"}
        actionSucceeded=$true;observedAtUtc=$effectTime.ToString('O');noInterruption=$noInterruption}|ConvertTo-Json|Set-Content $evidencePath
    $phase=switch($TestId){'HA-REPLICA-001'{'app-instance'}'HA-DB-001'{'failover'}'HA-COMBINED-001'{'combined'}}
    foreach($window in @(60,300)){
        $path=Join-Path $CaseRoot "recovery-$window.json"
        $arguments=@{AttemptsPath=$AttemptsPath;FailoverEvidencePath=$evidencePath;WorkloadPhase=$phase;WindowSeconds=$window;OutputPath=$path}
        if($window -eq 300){$arguments.MinimumCanarySuccessRate=0.999}
        & (Get-Process -Id $PID).Path -NoProfile -File "$PSScriptRoot\evaluate-recovery.ps1" @arguments|Out-Null
        $exit=$LASTEXITCODE
        $evaluation=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable
        if($window -eq 60){$result.recovery=$evaluation}else{$result.stable=$evaluation}
        if($exit -ne 0 -or $evaluation.status -ne 'PASS'){
            $prefix=if($evaluation.status -eq 'FAIL'){'FAIL'}else{'INCONCLUSIVE'}
            $failures.Add("${prefix}: $window-second recovery/stability evaluation is $($evaluation.status): $($evaluation.reason)")
        }
    }
    if($database -and $result.recovery.status -eq 'PASS' -and $result.recovery.recoveryDurationSeconds -gt 180){$failures.Add('FAIL: database/combined recovery exceeded 180 seconds.')}
    $lastTick=[DateTimeOffset](@($events|Where-Object type -eq canaryTick|Sort-Object scheduledAtUtc)[-1].scheduledAtUtc)
    if($database -and ($lastTick-$effectTime).TotalSeconds -lt 600){throw 'INCONCLUSIVE: less than ten minutes of post-database-effect measurement.'}
    if($failures.Count){
        $result.status=if(@($failures|Where-Object {$_ -like 'FAIL:*'}).Count){'FAIL'}else{'INCONCLUSIVE'}
        $result.reason=$failures -join ' '
        Write-Warning $result.reason
    }else{
        $result.status='PASS'
        $result.reason='Intended replica/database effects and survivor traffic were independently evidenced; recovery and stability windows qualified. Full-phase availability is reported separately.'
    }
}catch{
    $result.status=if($_.Exception.Message -like 'FAIL:*'){'FAIL'}else{'INCONCLUSIVE'}
    $result.reason=$_.Exception.Message
    Write-Warning $result.reason
}finally{
    $result|ConvertTo-Json -Depth 30|Set-Content (Join-Path $CaseRoot 'effect-verdict.json')
}
if($result.status -ne 'PASS'){exit 1}
