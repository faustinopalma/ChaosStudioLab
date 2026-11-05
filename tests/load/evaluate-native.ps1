[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $AttemptsPath,
    [Parameter(Mandatory)][string] $ObserverPath,
    [Parameter(Mandatory)][string] $CaseRoot,
    [Parameter(Mandatory)][ValidateSet('HA-APP-001','HA-APP-ZONE-001','HA-DB-001','HA-COMBINED-001')][string] $TestId,
    [Parameter(Mandatory)][DateTimeOffset] $SubmittedAtUtc,
    [Parameter(Mandatory)][object[]] $BeforeInstances,
    [Parameter(Mandatory)][object[]] $BeforeObservations,
    [string[]] $TargetInstanceIds=@(),
    [Parameter(Mandatory)][hashtable] $PostgresBefore,
    [Parameter(Mandatory)][hashtable] $PostgresAfter
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$result=@{status='INCONCLUSIVE';reason='Required native effect evidence is incomplete.';processChanges=@();recovery=$null;stable=$null}
function Read-Events([string]$Path) {
    @(Get-Content -LiteralPath $Path | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json -AsHashtable })
}
function Get-Time([object]$Value) { [DateTimeOffset]$Value }
try {
    $events=Read-Events $AttemptsPath
    $observations=Read-Events $ObserverPath
    $application=$TestId -ne 'HA-DB-001'
    $database=$TestId -in @('HA-DB-001','HA-COMBINED-001')
    $effectTime=$null
    if($application) {
        if($TargetInstanceIds.Count -eq 0) { throw 'INCONCLUSIVE: no exact instance set was provided for process-effect evaluation.' }
        foreach($id in $TargetInstanceIds) {
            $old=@($BeforeObservations | Where-Object { $_.instanceId -ceq $id -and $_.processStartedAtUtc } |
                Sort-Object observedAtUtc | Select-Object -Last 1)
            $changed=@($observations | Where-Object {
                $_.kind -eq 'live' -and $_.statusCode -eq 200 -and $_.instanceId -ceq $id -and
                $_.processStartedAtUtc -and (Get-Time $_.processStartedAtUtc) -ge $SubmittedAtUtc -and
                $old.Count -eq 1 -and (Get-Time $_.processStartedAtUtc) -gt (Get-Time $old[0].processStartedAtUtc)
            } | Sort-Object observedAtUtc | Select-Object -First 1)
            if($changed.Count -ne 1) { throw "INCONCLUSIVE: exact targeted worker $id lacks independently observed post-injection process replacement." }
            $result.processChanges+=@(@{instanceId=$id;before=$old[0];after=$changed[0]})
        }
        $effectTime=Get-Time ($result.processChanges.after.processStartedAtUtc | Sort-Object | Select-Object -Last 1)
        $survivingIds=@($BeforeInstances | Where-Object { $_.name -notin $TargetInstanceIds } | ForEach-Object name)
        foreach($id in $survivingIds) {
            if(-not @($observations | Where-Object {
                $_.kind -eq 'live' -and $_.instanceId -ceq $id -and $_.statusCode -eq 200 -and
                (Get-Time $_.requestedAtUtc) -gt $SubmittedAtUtc
            }).Count) { throw "INCONCLUSIVE: surviving worker $id has no independent healthy observation." }
        }
    }
    if($database) {
        if($PostgresAfter.state -ne 'Ready' -or $PostgresAfter.highAvailability.state -ne 'Healthy' -or
            $PostgresAfter.highAvailability.mode -ne 'ZoneRedundant' -or
            $PostgresAfter.availabilityZone -cne $PostgresBefore.highAvailability.standbyAvailabilityZone -or
            $PostgresAfter.highAvailability.standbyAvailabilityZone -cne $PostgresBefore.availabilityZone) {
            throw 'INCONCLUSIVE: native database completion lacks the independently verified healthy primary/standby zone swap.'
        }
        $dependency=@($observations | Where-Object {
            $_.kind -eq 'dependencies' -and (Get-Time $_.requestedAtUtc) -ge $SubmittedAtUtc
        } | Sort-Object requestedAtUtc)
        $bad=@($dependency | Where-Object {
            $_.statusCode -eq 503 -and $_.processId -and $_.dependencyStatus -in @('unavailable','timeout')
        })
        if($bad.Count -eq 0) { throw 'INCONCLUSIVE: role swap occurred, but no independently observed application database disruption bounds recovery.' }
        $databaseEffect=Get-Time $bad[0].observedAtUtc
        if($TestId -eq 'HA-COMBINED-001') {
            foreach($change in $result.processChanges) {
                $restart=Get-Time $change.after.processStartedAtUtc
                $left=@($bad | Where-Object { (Get-Time $_.observedAtUtc) -lt $restart } | Select-Object -Last 1)
                $right=@($bad | Where-Object { (Get-Time $_.requestedAtUtc) -gt $restart } | Select-Object -First 1)
                if($left.Count -ne 1 -or $right.Count -ne 1 -or
                    @($dependency | Where-Object {
                        $_.statusCode -eq 200 -and (Get-Time $_.requestedAtUtc) -ge (Get-Time $left[0].observedAtUtc) -and
                        (Get-Time $_.observedAtUtc) -le (Get-Time $right[0].requestedAtUtc)
                    }).Count) { throw 'INCONCLUSIVE: independently observed application replacement and database disruptive intervals did not establish overlap.' }
            }
            $result.overlap='Every targeted process replacement was bracketed by independently observed database-dependency failures, with no intervening healthy dependency sample.'
        }
        $effectTime=$databaseEffect
    }
    $evidencePath=Join-Path $CaseRoot 'independent-effect.json'
    @{schemaVersion=1;source='private independent observer plus actual process identity and ARM primary/standby inventory'
        targetResourceId=if($database) {$PostgresBefore.id} else {$BeforeInstances[0].id -replace '/instances/[^/]+$',''}
        actionSucceeded=$true;observedAtUtc=$effectTime.ToString('O');noInterruption=$false} |
        ConvertTo-Json -Depth 10 | Set-Content $evidencePath -Encoding utf8
    $phase=switch($TestId) { 'HA-APP-001' {'app-instance'} 'HA-APP-ZONE-001' {'app-zone'} 'HA-DB-001' {'failover'} 'HA-COMBINED-001' {'combined'} }
    if($database) {
        foreach($window in @(60,300)) {
            $path=Join-Path $CaseRoot "recovery-$window.json"
            $arguments=@{AttemptsPath=$AttemptsPath;FailoverEvidencePath=$evidencePath;WorkloadPhase=$phase
                WindowSeconds=$window;OutputPath=$path}
            if($window -eq 300) { $arguments.MinimumCanarySuccessRate=0.999 }
            & (Get-Process -Id $PID).Path -NoLogo -NoProfile -File (Join-Path $PSScriptRoot 'evaluate-recovery.ps1') @arguments
            $evaluation=Get-Content $path -Raw | ConvertFrom-Json
            if($window -eq 60) { $result.recovery=$evaluation } else { $result.stable=$evaluation }
            if($LASTEXITCODE -ne 0 -or $evaluation.status -ne 'PASS') { throw 'INCONCLUSIVE: recovery/stable observation lacks a complete qualifying window.' }
        }
        if($result.recovery.recoveryDurationSeconds -gt 180) { throw 'FAIL: database/combined recovery exceeded 180 seconds.' }
        $lastEvent=Get-Time ($events | Where-Object type -eq canaryTick | Sort-Object scheduledAtUtc | Select-Object -Last 1).scheduledAtUtc
        if(($lastEvent-$effectTime).TotalSeconds -lt 600) { throw 'INCONCLUSIVE: less than ten minutes after independently observed database disruption.' }
    } else {
        $start=[DateTimeOffset]::FromUnixTimeSeconds([long][Math]::Ceiling($effectTime.ToUnixTimeMilliseconds()/1000.0))
        $end=$start.AddSeconds(300)
        $operations=@($events | Where-Object {
            $_.type -eq 'businessOperation' -and $_.phase -eq $phase -and
            (Get-Time $_.startedAtUtc) -ge $start -and (Get-Time $_.startedAtUtc) -lt $end
        })
        $drops=@($events | Where-Object {
            $_.type -eq 'droppedScheduledOperation' -and $_.scenario -eq 'workload' -and
            (Get-Time $_.recordedAtUtc) -ge $start -and (Get-Time $_.recordedAtUtc) -lt $end
        })
        $dropCount=0.0
        foreach($drop in $drops) { $dropCount+=[double]$drop.count }
        $canaries=@($events | Where-Object {
            $_.type -eq 'canaryTick' -and (Get-Time $_.scheduledAtUtc) -ge $start -and (Get-Time $_.scheduledAtUtc) -lt $end
        } | Sort-Object scheduledAtUtc)
        $seconds=@($canaries | ForEach-Object { [long][Math]::Floor((Get-Time $_.scheduledAtUtc).ToUnixTimeMilliseconds()/1000.0) } | Sort-Object -Unique)
        if($operations.Count+$dropCount -ne 6000 -or $canaries.Count -ne 300 -or $seconds.Count -ne 300) {
            throw 'INCONCLUSIVE: the first five post-effect minutes lack complete expected business/canary accounting.'
        }
        $successes=@($operations | Where-Object success)
        $latencies=@($successes.durationMs | Sort-Object)
        $p95=if($latencies.Count) { $latencies[[Math]::Ceiling(0.95*$latencies.Count)-1] } else { [double]::PositiveInfinity }
        $maximum=0; $streak=0
        foreach($tick in $canaries) {
            if(-not $tick.ContainsKey('readSucceeded') -or -not $tick.ContainsKey('writeSucceeded')) { throw 'INCONCLUSIVE: canary evidence lacks distinct read/write outcomes.' }
            if(-not $tick.readSucceeded -and -not $tick.writeSucceeded) { $streak++; $maximum=[Math]::Max($maximum,$streak) } else { $streak=0 }
        }
        $result.firstFiveMinutes=@{startedAtUtc=$start.ToString('O');businessOperations=$operations.Count;drops=$dropCount
            successRate=$successes.Count/6000.0;p95Ms=$p95;maximumCompleteCanaryFailureSeconds=$maximum}
        if($successes.Count/6000.0 -lt 0.99 -or $p95 -gt 2000 -or $maximum -gt 5) { throw 'FAIL: application post-effect availability, latency or complete-unavailability limit exceeded.' }
    }
    $result.status='PASS'
    $result.reason='Exact native effects, required observation windows and measured acceptance passed; full-phase availability and full write-history retention are reported separately.'
} catch {
    $result.status=if($_.Exception.Message -like 'FAIL:*') {'FAIL'} else {'INCONCLUSIVE'}
    $result.reason=$_.Exception.Message
    throw
} finally {
    $result | ConvertTo-Json -Depth 25 | Set-Content (Join-Path $CaseRoot 'effect-verdict.json') -Encoding utf8
}
