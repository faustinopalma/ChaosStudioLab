[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $AttemptsPath,

    [Parameter(Mandatory)]
    [string] $FailoverEvidencePath,

    [Parameter(Mandatory)]
    [string] $WorkloadPhase,

    [Parameter()]
    [ValidateRange(1, 3600)]
    [int] $WindowSeconds = 60,

    [Parameter()]
    [ValidateRange(1, 10000)]
    [int] $ExpectedOperationsPerSecond = 20,

    [Parameter()]
    [ValidateRange(0, 1)]
    [double] $MinimumCanarySuccessRate = 0.99,

    [Parameter()]
    [ValidateRange(1, 60000)]
    [double] $SuccessfulOperationP95LimitMs = 1000,

    [Parameter()]
    [string] $OutputPath
)

$ErrorActionPreference = 'Stop'

function Get-TimestampText([object] $Value) {
    if ($Value -is [DateTime]) {
        if ($Value.Kind -eq [DateTimeKind]::Unspecified) {
            $Value = [DateTime]::SpecifyKind($Value, [DateTimeKind]::Utc)
        }
        return $Value.ToUniversalTime().ToString('O')
    }
    if ($Value -is [DateTimeOffset]) { return $Value.ToUniversalTime().ToString('O') }
    return [string] $Value
}

if (-not (Test-Path -LiteralPath $AttemptsPath -PathType Leaf)) {
    throw "Attempt event file does not exist: $AttemptsPath"
}
if (-not (Test-Path -LiteralPath $FailoverEvidencePath -PathType Leaf)) {
    throw "Failover evidence file does not exist: $FailoverEvidencePath"
}

$evidence = Get-Content -LiteralPath $FailoverEvidencePath -Raw | ConvertFrom-Json
$evidenceTime = [DateTimeOffset]::MinValue
$evidenceValid = $evidence.schemaVersion -eq 1 `
    -and $evidence.actionSucceeded -eq $true `
    -and -not [string]::IsNullOrWhiteSpace($evidence.source) `
    -and -not [string]::IsNullOrWhiteSpace($evidence.targetResourceId) `
    -and [DateTimeOffset]::TryParse(
        (Get-TimestampText $evidence.observedAtUtc),
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal,
        [ref] $evidenceTime)

$events = @(
    Get-Content -LiteralPath $AttemptsPath |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { ConvertFrom-Json $_ }
)
if ($events.Count -eq 0) {
    throw 'Attempt event file contains no events.'
}

$runIds = @($events | ForEach-Object { $_.runId } | Sort-Object -Unique)
if ($runIds.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string] $runIds[0])) {
    throw 'Attempt events must contain one consistent, non-empty runId.'
}

$canaryBySecond = @{}
foreach ($tick in @($events | Where-Object { $_.type -eq 'canaryTick' })) {
    $timestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            (Get-TimestampText $tick.scheduledAtUtc),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref] $timestamp)) {
        throw "Invalid canary timestamp in run $($runIds[0])."
    }

    $second = [long][Math]::Floor($timestamp.ToUnixTimeMilliseconds() / 1000.0)
    if (-not $canaryBySecond.ContainsKey($second)) {
        $canaryBySecond[$second] = [System.Collections.Generic.List[object]]::new()
    }
    $canaryBySecond[$second].Add($tick)
}

$businessOperations = @(
    foreach ($event in @($events | Where-Object {
        $_.type -eq 'businessOperation' `
            -and $_.phase -eq $WorkloadPhase `
            -and $_.operation -in @('read', 'write') `
    })) {
        $timestamp = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse(
                (Get-TimestampText $event.startedAtUtc),
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal,
                [ref] $timestamp)) {
            throw "Invalid workload timestamp in run $($runIds[0])."
        }
        [pscustomobject]@{
            Second = [long][Math]::Floor($timestamp.ToUnixTimeMilliseconds() / 1000.0)
            DurationMs = [double] $event.durationMs
            Success = $event.success -eq $true
        }
    }
)

$workloadDropsBySecond = @{}
foreach ($drop in @($events | Where-Object {
    $_.type -eq 'droppedScheduledOperation' -and $_.scenario -eq 'workload'
})) {
    $timestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
            (Get-TimestampText $drop.recordedAtUtc),
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeUniversal,
            [ref] $timestamp)) {
        throw "Invalid dropped-operation timestamp in run $($runIds[0])."
    }

    $second = [long][Math]::Floor($timestamp.ToUnixTimeMilliseconds() / 1000.0)
    if (-not $workloadDropsBySecond.ContainsKey($second)) {
        $workloadDropsBySecond[$second] = 0.0
    }
    $workloadDropsBySecond[$second] += [double] $drop.count
}

$qualifyingWindow = $null
$completeWindowCount = 0
$incompleteWindowCount = 0
$disruptionTime = $null

if ($evidenceValid -and $canaryBySecond.Count -gt 0) {
    $disruptionTime = $evidenceTime.ToUniversalTime()
    $firstCandidateSecond = [long][Math]::Ceiling(
        $disruptionTime.ToUnixTimeMilliseconds() / 1000.0)
    $lastObservedSecond = [long](($canaryBySecond.Keys | Measure-Object -Maximum).Maximum)
    $lastCandidateSecond = $lastObservedSecond - $WindowSeconds + 1

    for ($startSecond = $firstCandidateSecond;
        $startSecond -le $lastCandidateSecond;
        $startSecond++) {
        $windowCanary = @()
        $missingCanarySeconds = 0
        for ($second = $startSecond; $second -lt ($startSecond + $WindowSeconds); $second++) {
            $secondTicks = $canaryBySecond[$second]
            if ($null -eq $secondTicks -or $secondTicks.Count -ne 1) {
                $missingCanarySeconds++
            } else {
                $windowCanary += $secondTicks[0]
            }
        }

        $windowStart = [DateTimeOffset]::FromUnixTimeSeconds($startSecond)
        $windowEnd = $windowStart.AddSeconds($WindowSeconds)
        $windowWorkload = @(
            $businessOperations | Where-Object {
                $_.Second -ge $startSecond -and $_.Second -lt ($startSecond + $WindowSeconds)
            }
        )
        $windowDropped = 0.0
        for ($second = $startSecond; $second -lt ($startSecond + $WindowSeconds); $second++) {
            if ($workloadDropsBySecond.ContainsKey($second)) {
                $windowDropped += $workloadDropsBySecond[$second]
            }
        }
        $expectedBusinessOperations = $ExpectedOperationsPerSecond * $WindowSeconds
        if ($missingCanarySeconds -gt 0 `
            -or ($windowWorkload.Count + $windowDropped) -ne $expectedBusinessOperations) {
            $incompleteWindowCount++
            continue
        }

        $completeWindowCount++
        $canarySuccesses = @($windowCanary | Where-Object { $_.success -eq $true }).Count
        $canaryRate = $canarySuccesses / $WindowSeconds
        $successfulOperations = @($windowWorkload | Where-Object { $_.Success })
        $businessSuccessRate = $successfulOperations.Count / $expectedBusinessOperations
        $sortedDurations = @($successfulOperations | ForEach-Object { $_.DurationMs } | Sort-Object)
        $p95Ms = $null
        if ($sortedDurations.Count -gt 0) {
            $p95Index = [Math]::Max(
                0,
                [int][Math]::Ceiling(0.95 * $sortedDurations.Count) - 1)
            $p95Ms = [double] $sortedDurations[$p95Index]
        }

        if ($canaryRate -ge $MinimumCanarySuccessRate `
            -and $businessSuccessRate -ge $MinimumCanarySuccessRate `
            -and $null -ne $p95Ms `
            -and $p95Ms -le $SuccessfulOperationP95LimitMs) {
            $qualifyingWindow = [pscustomobject]@{
                startsAtUtc = $windowStart.ToString('O')
                endsAtUtc = $windowEnd.ToString('O')
                canarySuccesses = $canarySuccesses
                canaryExpected = $WindowSeconds
                canarySuccessRate = [Math]::Round($canaryRate, 6)
                successfulBusinessOperations = $successfulOperations.Count
                expectedBusinessOperations = $expectedBusinessOperations
                droppedScheduledOperations = $windowDropped
                businessOperationSuccessRate = [Math]::Round($businessSuccessRate, 6)
                successfulOperationP95Ms = $p95Ms
            }
            break
        }
    }
}

$status = 'INCONCLUSIVE'
$reason = 'A complete qualifying recovery window could not be established from the available evidence.'
$recoveryDurationSeconds = $null
if (-not $evidenceValid) {
    $reason = 'Failover evidence is invalid or incomplete; an independent successful action, target, source, and UTC observation time are required.'
} elseif ($null -eq $disruptionTime) {
    $reason = 'No canary ticks were recorded after the evidenced failover.'
} elseif ($null -ne $qualifyingWindow) {
    $windowStartTime = [DateTimeOffset]::Parse($qualifyingWindow.startsAtUtc).ToUniversalTime()
    $recoveryDurationSeconds = [Math]::Round(
        ($windowStartTime - $disruptionTime).TotalSeconds,
        3)
    if ($recoveryDurationSeconds -eq 0 -and $evidence.noInterruption -ne $true) {
        $reason = 'Zero recovery duration requires independent evidence that failover occurred without an application interruption.'
    } else {
        $status = 'PASS'
        $reason = 'A complete recovery window met the configured canary and successful-operation p95 thresholds.'
    }
} elseif ($completeWindowCount -gt 0) {
    $status = 'FAIL'
    $reason = 'At least one complete observation window was evaluated, but none met the configured recovery thresholds.'
}

$report = [ordered]@{
    schemaVersion = 1
    runId = [string] $runIds[0]
    status = $status
    reason = $reason
    workloadPhase = $WorkloadPhase
    failoverEvidence = [ordered]@{
        source = $evidence.source
        targetResourceId = $evidence.targetResourceId
        actionSucceeded = $evidence.actionSucceeded
        observedAtUtc = if ($evidenceValid) { $disruptionTime.ToString('O') } else { $evidence.observedAtUtc }
        noInterruption = $evidence.noInterruption
    }
    criteria = [ordered]@{
        windowSeconds = $WindowSeconds
        expectedOperationsPerSecond = $ExpectedOperationsPerSecond
        minimumCanarySuccessRate = $MinimumCanarySuccessRate
        successfulOperationP95LimitMs = $SuccessfulOperationP95LimitMs
    }
    evaluatedCompleteWindows = $completeWindowCount
    skippedIncompleteWindows = $incompleteWindowCount
    recoveryDurationSeconds = $recoveryDurationSeconds
    qualifyingWindow = $qualifyingWindow
}

$json = $report | ConvertTo-Json -Depth 20
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Output $json
} else {
    $resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    Set-Content -LiteralPath $resolvedOutputPath -Value $json -Encoding utf8
    Write-Output $resolvedOutputPath
}

if ($status -eq 'FAIL') {
    exit 1
}
if ($status -eq 'INCONCLUSIVE') {
    exit 2
}
