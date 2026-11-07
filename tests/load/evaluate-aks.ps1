param(
    [Parameter(Mandatory)][string] $AttemptsPath,
    [Parameter(Mandatory)][string] $TopologyPath,
    [Parameter(Mandatory)][string] $ObserverPath,
    [Parameter(Mandatory)][string] $CaseRoot,
    [Parameter(Mandatory)][ValidateSet('HA-NODE-001','HA-ZONE-COMPUTE-001','HA-DB-001','HA-COMBINED-001')][string] $TestId,
    [Parameter(Mandatory)][DateTimeOffset] $SubmittedAtUtc,
    [Parameter(Mandatory)][AllowEmptyCollection()][string[]] $TargetVmIds,
    [Parameter(Mandatory)][hashtable] $PostgresBefore,
    [Parameter(Mandatory)][hashtable] $PostgresAfter
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$result=@{status='INCONCLUSIVE';reason='Required independently observed effects are incomplete.';compute=$null;overlap=$null;recovery=$null;stable=$null}
$failures=[Collections.Generic.List[string]]::new()
function Read-Events([string]$Path){@(Get-Content $Path|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})}
try{
    $events=Read-Events $AttemptsPath
    $topology=Read-Events $TopologyPath
    $observer=Read-Events $ObserverPath
    $compute=$TestId -ne 'HA-DB-001'
    $database=$TestId -in @('HA-DB-001','HA-COMBINED-001')
    $effectTime=$null
    if($compute){
        if($TargetVmIds.Count -ne $(if($TestId -eq 'HA-NODE-001'){1}else{3})){throw 'INCONCLUSIVE: exact node or complete selected-zone VM set is missing.'}
        $initial=$topology[0]
        $survivors=@($initial.vms|Where-Object {$_.id -notin $TargetVmIds})
        $firstOff=$null;$lastOff=$null;$qualified=$null
        foreach($sample in $topology){
            $time=([DateTimeOffset]$sample.observedAtUtc).ToUniversalTime()
            if([DateTimeOffset]$sample.requestedAtUtc -lt $SubmittedAtUtc){continue}
            $off=@($sample.vms|Where-Object {$_.id -in $TargetVmIds -and $_.powerState -in @('PowerState/stopped','PowerState/deallocated')})
            $healthy=@($sample.vms|Where-Object {$_.id -in $survivors.id -and $_.powerState -eq 'PowerState/running'})
            $unplanned=@($sample.vms|Where-Object {$_.id -notin $initial.vms.id})
            $valid=$off.Count -eq $TargetVmIds.Count -and $healthy.Count -eq $survivors.Count -and -not $unplanned.Count
            if(-not $valid -or ($null -ne $lastOff -and ($time-$lastOff).TotalSeconds -gt 30)){
                $firstOff=$null;$lastOff=$null
                continue
            }
            if($null -eq $firstOff){$firstOff=$time}
            $lastOff=$time
            if(($lastOff-$firstOff).TotalSeconds -ge 300 -and $null -eq $qualified){
                $qualified=@{startedAtUtc=$firstOff.ToString('O');verifiedThroughUtc=$lastOff.ToString('O')
                    minimumVerifiedSeconds=($lastOff-$firstOff).TotalSeconds;targetVmIds=$TargetVmIds;survivingVmIds=@($survivors.id);maximumSampleGapSeconds=30}
            }
        }
        if($null -eq $qualified){throw 'INCONCLUSIVE: no continuous >=300-second independently sampled shutdown of every intended VM with surviving nodes powered on and no replacement IDs.'}
        $result.compute=$qualified
        $effectTime=[DateTimeOffset]$qualified.startedAtUtc
        $outageEnd=[DateTimeOffset]$qualified.verifiedThroughUtc
        $podZones=@{}
        foreach($sample in $topology){
            foreach($pod in $sample.pods.items){
                $node=@($sample.nodes.items|Where-Object {$_.metadata.name -eq $pod.spec.nodeName})
                if($node.Count -eq 1){$podZones[$pod.metadata.uid]=$node[0].metadata.labels.'topology.kubernetes.io/zone'}
            }
        }
        $traffic=@($events|Where-Object { $_.type -eq 'attempt' -and $_.success -eq $true -and
            [DateTimeOffset]$_.recordedAtUtc -ge $effectTime -and [DateTimeOffset]$_.recordedAtUtc -le $outageEnd})
        $trafficZones=@($traffic|ForEach-Object {$podZones[$_.instanceId]}|Where-Object {$_}|Sort-Object -Unique)
        if($trafficZones.Count -lt 2){throw 'INCONCLUSIVE: fewer than two observed surviving zones delivered successful business traffic during the sustained node outage.'}
        $result.compute.survivingTrafficZones=$trafficZones
        if(-not $database){
            $windowStart=[DateTimeOffset]::FromUnixTimeSeconds([long][Math]::Ceiling($effectTime.ToUnixTimeMilliseconds()/1000.0))
            $windowEnd=$windowStart.AddSeconds(300)
            $operations=@($events|Where-Object {$_.type -eq 'businessOperation' -and
                [DateTimeOffset]$_.startedAtUtc -ge $windowStart -and [DateTimeOffset]$_.startedAtUtc -lt $windowEnd})
            $drops=@($events|Where-Object {$_.type -eq 'droppedScheduledOperation' -and $_.scenario -eq 'workload' -and
                [DateTimeOffset]$_.recordedAtUtc -ge $windowStart -and [DateTimeOffset]$_.recordedAtUtc -lt $windowEnd})
            $dropCount=0.0;foreach($drop in $drops){$dropCount+=[double]$drop.count}
            $ticks=@($events|Where-Object {$_.type -eq 'canaryTick' -and
                [DateTimeOffset]$_.scheduledAtUtc -ge $windowStart -and [DateTimeOffset]$_.scheduledAtUtc -lt $windowEnd}|Sort-Object scheduledAtUtc)
            $tickSeconds=@($ticks|ForEach-Object {[long][Math]::Floor(([DateTimeOffset]$_.scheduledAtUtc).ToUnixTimeMilliseconds()/1000.0)}|Sort-Object -Unique)
            if($operations.Count+$dropCount -ne 6000 -or $ticks.Count -ne 300 -or $tickSeconds.Count -ne 300){
                throw 'INCONCLUSIVE: first five-minute post-compute-effect window lacks complete business/canary sampling.'
            }
            $success=@($operations|Where-Object success -eq $true)
            $durations=@($success|ForEach-Object {[double]$_.durationMs}|Sort-Object)
            $p95=if($durations.Count){$durations[[Math]::Max(0,[int][Math]::Ceiling(0.95*$durations.Count)-1)]}else{$null}
            $consecutive=0;$longest=0
            foreach($tick in $ticks){if($tick.success){$consecutive=0}else{$consecutive++;$longest=[Math]::Max($longest,$consecutive)}}
            $window=@{startedAtUtc=$windowStart.ToString('O');endedAtUtc=$windowEnd.ToString('O');businessSuccessRate=$success.Count/6000.0
                successfulOperationP95Ms=$p95;droppedOperations=$dropCount;longestCompleteUnavailabilitySeconds=$longest;expectedBusinessOperations=6000;expectedCanaries=300}
            $result.compute.firstFiveMinutes=$window
            if($window.businessSuccessRate -lt 0.99 -or $null -eq $p95 -or $p95 -gt 2000 -or $longest -gt 5){
                $window.status='FAIL'
                $failures.Add('FAIL: first five-minute compute-only observation exceeded 99% business success, two-second p95 or five-second complete-unavailability limits.')
            }else{$window.status='PASS'}
        }
    }
    if($database){
        if($PostgresAfter.state -ne 'Ready' -or $PostgresAfter.highAvailability.mode -ne 'ZoneRedundant' -or
            $PostgresAfter.highAvailability.state -ne 'Healthy' -or
            $PostgresAfter.availabilityZone -cne $PostgresBefore.highAvailability.standbyAvailabilityZone -or
            $PostgresAfter.highAvailability.standbyAvailabilityZone -cne $PostgresBefore.availabilityZone){
            throw 'INCONCLUSIVE: independently captured PostgreSQL healthy primary/standby zone swap is missing.'
        }
        $dependency=@($observer|Where-Object {$_.kind -eq 'dependencies' -and [DateTimeOffset]$_.requestedAtUtc -ge $SubmittedAtUtc})
        $bad=@($dependency|Where-Object {$_.statusCode -eq 503 -and $_.processId -and $_.dependencyStatus -in @('timeout','unavailable')})
        if(-not $bad.Count){throw 'INCONCLUSIVE: no independently observed database disruption bounds recovery.'}
        if($compute){
            $left=@($bad|Where-Object {[DateTimeOffset]$_.observedAtUtc -le $effectTime}|Select-Object -Last 1)
            $right=@($bad|Where-Object {[DateTimeOffset]$_.requestedAtUtc -ge $effectTime -and [DateTimeOffset]$_.observedAtUtc -le $outageEnd}|Select-Object -First 1)
            if($left.Count -ne 1 -or $right.Count -ne 1 -or @($dependency|Where-Object {
                $_.statusCode -eq 200 -and [DateTimeOffset]$_.requestedAtUtc -ge [DateTimeOffset]$left[0].observedAtUtc -and
                [DateTimeOffset]$_.observedAtUtc -le [DateTimeOffset]$right[0].requestedAtUtc
            }).Count){throw 'INCONCLUSIVE: independently observed database failures do not bracket actual selected-zone node shutdown.'}
            $result.overlap=@{status='PASS';databaseFailureBefore=$left[0];computeOffAtUtc=$effectTime.ToString('O');databaseFailureAfter=$right[0]}
        }
        $effectTime=([DateTimeOffset]$bad[0].observedAtUtc).ToUniversalTime()
    }
    $evidencePath=Join-Path $CaseRoot 'independent-effect.json'
    $noInterruption=$false
    if(-not $database){
        $near=@($observer|Where-Object {[DateTimeOffset]$_.requestedAtUtc -ge $effectTime.AddSeconds(-10) -and
            [DateTimeOffset]$_.observedAtUtc -le $effectTime.AddSeconds(60)})
        $noInterruption=@($near|Where-Object kind -eq live).Count -ge 10 -and @($near|Where-Object kind -eq dependencies).Count -ge 10 -and
            -not @($near|Where-Object {$_.statusCode -ne 200}).Count
    }
    @{schemaVersion=1;source='private ARM VM instance power-state observer, private Kubernetes topology, private dependency probes and primary/standby inventory'
        targetResourceId=if($database){$PostgresBefore.id}else{$TargetVmIds[0]}
        actionSucceeded=$true;observedAtUtc=$effectTime.ToString('O');noInterruption=$noInterruption}|ConvertTo-Json|Set-Content $evidencePath
    $phase=switch($TestId){'HA-NODE-001'{'app-instance'}'HA-ZONE-COMPUTE-001'{'app-zone'}'HA-DB-001'{'failover'}'HA-COMBINED-001'{'combined'}}
    foreach($window in @(60,300)){
        $path=Join-Path $CaseRoot "recovery-$window.json"
        $arguments=@{AttemptsPath=$AttemptsPath;FailoverEvidencePath=$evidencePath;WorkloadPhase=$phase;WindowSeconds=$window;OutputPath=$path}
        if($window -eq 300){$arguments.MinimumCanarySuccessRate=0.999}
        & (Get-Process -Id $PID).Path -NoProfile -File "$PSScriptRoot\evaluate-recovery.ps1" @arguments|Out-Null
        $exit=$LASTEXITCODE
        $evaluation=Get-Content $path -Raw|ConvertFrom-Json -AsHashtable
        if($window -eq 60){$result.recovery=$evaluation}else{$result.stable=$evaluation}
        if($exit -ne 0 -or $evaluation.status -ne 'PASS'){$failures.Add("INCONCLUSIVE: complete qualifying $window-second recovery or stable window is missing.")}
    }
    if($database -and $result.recovery.status -eq 'PASS' -and $result.recovery.recoveryDurationSeconds -gt 180){
        $failures.Add('FAIL: database/combined recovery exceeded 180 seconds.')
    }
    $lastTick=[DateTimeOffset](@($events|Where-Object type -eq canaryTick|Sort-Object scheduledAtUtc)[-1].scheduledAtUtc)
    if($database -and ($lastTick-$effectTime).TotalSeconds -lt 600){throw 'INCONCLUSIVE: less than ten minutes of post-database-effect measurement.'}
    if($failures.Count){
        $result.status=if(@($failures|Where-Object {$_ -like 'FAIL:*'}).Count){'FAIL'}else{'INCONCLUSIVE'}
        $result.reason=$failures -join ' '
        Write-Warning $result.reason
    }else{
        $result.status='PASS'
        $result.reason='Native Action succeeded, intended infrastructure/component effects and survivor traffic were independently evidenced, recovery/stability windows qualified. Full-phase availability is reported separately.'
    }
}catch{
    $result.status=if($_.Exception.Message -like 'FAIL:*'){'FAIL'}else{'INCONCLUSIVE'}
    $result.reason=$_.Exception.Message
    Write-Warning $result.reason
}finally{
    $result|ConvertTo-Json -Depth 30|Set-Content (Join-Path $CaseRoot 'effect-verdict.json')
}
if($result.status -ne 'PASS'){exit 1}
