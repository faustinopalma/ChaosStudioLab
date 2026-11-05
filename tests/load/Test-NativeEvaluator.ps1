$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Join-Path ([IO.Path]::GetTempPath()) "csl-native-evaluator-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root | Out-Null
$base=[DateTimeOffset]::Parse('2026-01-01T00:00:00Z')
$instances=@(0..5 | ForEach-Object { @{name="instance-$_";id="/subscriptions/fixture/resourceGroups/fixture/providers/Microsoft.Web/sites/fixture/instances/instance-$_"} })
$before=@(0..5 | ForEach-Object {
    @{instanceId="instance-$_";processId='100';processStartedAtUtc=$base.AddHours(-1).ToString('O');observedAtUtc=$base.AddSeconds(-1).ToString('O')}
})
$dbBefore=@{id='/subscriptions/fixture/resourceGroups/fixture/providers/Microsoft.DBforPostgreSQL/flexibleServers/fixture'
    state='Ready';availabilityZone='1';highAvailability=@{mode='ZoneRedundant';state='Healthy';standbyAvailabilityZone='2'}}
$dbAfter=@{state='Ready';availabilityZone='2';highAvailability=@{mode='ZoneRedundant';state='Healthy';standbyAvailabilityZone='1'}}
function Invoke-Case([string]$Name,[string]$TestId,[string]$Phase,[string]$Expected,[int]$RestartSecond=15,[string[]]$Targets=@('instance-0'),[switch]$UnverifiedDependency,[int]$DisruptionSecond=10,[string]$ExpectedReason) {
    $directory=Join-Path $root $Name
    New-Item -ItemType Directory -Path $directory | Out-Null
    $events=[Collections.Generic.List[string]]::new()
    $observations=[Collections.Generic.List[string]]::new()
    for($second=0;$second -lt 640;$second++) {
        $time=$base.AddSeconds($second)
        $events.Add((@{runId='fixture';type='canaryTick';scheduledAtUtc=$time.ToString('O');recordedAtUtc=$time.AddMilliseconds(10).ToString('O')
            durationMs=50;success=$true;readSucceeded=$true;writeSucceeded=$true} | ConvertTo-Json -Compress))
        for($operation=0;$operation -lt 20;$operation++) {
            $events.Add((@{runId='fixture';type='businessOperation';phase=$Phase;operation='read'
                startedAtUtc=$time.AddMilliseconds($operation*45).ToString('O');durationMs=100;success=$true} | ConvertTo-Json -Compress))
        }
        foreach($instance in 0..5) {
            $observations.Add((@{kind='live';statusCode=200;instanceId="instance-$instance";processId='101'
                processStartedAtUtc=if($instance -eq 0 -and $second -ge $RestartSecond) {$base.AddSeconds($RestartSecond).ToString('O')} else {$base.AddHours(-1).ToString('O')}
                requestedAtUtc=$time.ToString('O');observedAtUtc=$time.AddMilliseconds(10).ToString('O')} | ConvertTo-Json -Compress))
        }
        $disrupted=$second -ge $DisruptionSecond -and $second -le ($DisruptionSecond+20)
        $observations.Add((@{kind='dependencies';statusCode=if($disrupted) {503} else {200}
            dependencyStatus=if($disrupted) {if($UnverifiedDependency) {$null} else {'unavailable'}} else {'healthy'}
            processId='101';requestedAtUtc=$time.ToString('O');observedAtUtc=$time.AddMilliseconds(10).ToString('O')} | ConvertTo-Json -Compress))
    }
    $attempts=Join-Path $directory 'attempts.ndjson'
    $observer=Join-Path $directory 'observer.ndjson'
    $events | Set-Content $attempts
    $observations | Set-Content $observer
    $caught=$false
    try {
        & (Join-Path $PSScriptRoot 'evaluate-native.ps1') -AttemptsPath $attempts -ObserverPath $observer -CaseRoot $directory `
            -TestId $TestId -SubmittedAtUtc $base -BeforeInstances $instances -BeforeObservations $before `
            -TargetInstanceIds $Targets -PostgresBefore $dbBefore -PostgresAfter $dbAfter | Out-Null
    } catch { $caught=$true }
    $verdict=Get-Content (Join-Path $directory 'effect-verdict.json') -Raw | ConvertFrom-Json
    if($verdict.status -ne $Expected -or ($Expected -eq 'PASS' -and $caught)) {
        throw "$Name expected $Expected; got $($verdict.status): $($verdict.reason)"
    }
    if($ExpectedReason -and $verdict.reason -notlike $ExpectedReason) {
        throw "$Name failed for the wrong acceptance gate: $($verdict.reason)"
    }
}
try {
    Invoke-Case instance HA-APP-001 app-instance PASS
    Invoke-Case missing-zone-member HA-APP-ZONE-001 app-zone INCONCLUSIVE -Targets @('instance-0','instance-1')
    Invoke-Case database HA-DB-001 failover PASS -Targets @()
    Invoke-Case delayed-effect HA-DB-001 failover INCONCLUSIVE -Targets @() -DisruptionSecond 100 `
        -ExpectedReason '*ten minutes after independently observed database disruption*'
    Invoke-Case combined HA-COMBINED-001 combined PASS
    Invoke-Case non-overlap HA-COMBINED-001 combined INCONCLUSIVE -RestartSecond 100
    Invoke-Case unverified-dependency HA-COMBINED-001 combined INCONCLUSIVE -UnverifiedDependency
    'Native effects require every selected process, complete post-effect accounting, real database role swap, recovery/stability and independently bracketed overlap.'
} finally { Remove-Item -LiteralPath $root -Recurse }
