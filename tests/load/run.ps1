[CmdletBinding()]
param(
    [Parameter()]
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\..\.local\runs'),

    [Parameter()]
    [string] $Phase = 'baseline',

    [Parameter()]
    [string] $Duration = '10m',

    [Parameter()]
    [ValidateRange(1, 100000)]
    [int] $Rate = 20,

    [Parameter()]
    [ValidateRange(0, 1)]
    [double] $MinimumBusinessOperationSuccessRate = 0.999,

    [Parameter()]
    [ValidateRange(1, 60000)]
    [int] $SuccessfulOperationP95LimitMs = 1000
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:API_BASE_URL) -or
    [string]::IsNullOrWhiteSpace($env:API_TOKEN)) {
    throw 'Set API_BASE_URL and API_TOKEN in the private runner environment.'
}

$apiUri = [Uri]::Empty
if (-not [Uri]::TryCreate($env:API_BASE_URL, [UriKind]::Absolute, [ref] $apiUri) -or
    $apiUri.Scheme -ne 'https') {
    throw 'API_BASE_URL must be an absolute HTTPS URL.'
}

$k6 = Get-Command 'k6' -ErrorAction SilentlyContinue
if ($null -eq $k6) {
    throw 'k6 is not installed or is not available on PATH.'
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$runId = [Guid]::NewGuid().ToString('N')
$runDirectory = Join-Path $resolvedOutputRoot $runId
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$consolePath = Join-Path $runDirectory 'k6-console.log'
$summaryPath = Join-Path $runDirectory 'summary.json'
$metricsPath = Join-Path $runDirectory 'metrics.ndjson'
$attemptsPath = Join-Path $runDirectory 'attempts.ndjson'
$reportPath = Join-Path $runDirectory 'run.json'
$scenarioPath = Join-Path $PSScriptRoot 'scenario.js'
$startedAt = [DateTimeOffset]::UtcNow

$previousEnvironment = @{
    RUN_ID = $env:RUN_ID
    PHASE = $env:PHASE
    DURATION = $env:DURATION
    RATE = $env:RATE
    SUCCESS_P95_LIMIT_MS = $env:SUCCESS_P95_LIMIT_MS
}

try {
    $env:RUN_ID = $runId
    $env:PHASE = $Phase
    $env:DURATION = $Duration
    $env:RATE = [string] $Rate
    $env:SUCCESS_P95_LIMIT_MS = [string] $SuccessfulOperationP95LimitMs

    & $k6.Source run `
        --log-format raw `
        --summary-export $summaryPath `
        --out "json=$metricsPath" `
        $scenarioPath *> $consolePath
    $exitCode = $LASTEXITCODE

    $attempts = [System.Collections.Generic.List[string]]::new()
    foreach ($line in Get-Content -LiteralPath $consolePath) {
        if ($line -match 'LAB_EVENT (\{.*\})') {
            $attempts.Add($Matches[1])
        }
    }

    if (Test-Path -LiteralPath $metricsPath) {
        foreach ($line in [System.IO.File]::ReadLines($metricsPath)) {
            $metric = ConvertFrom-Json $line
            if ($metric.metric -eq 'dropped_iterations' -and $metric.type -eq 'Point') {
                if ($null -eq $metric.data.time -or
                    $null -eq $metric.data.value -or
                    [string]::IsNullOrWhiteSpace([string] $metric.data.tags.scenario)) {
                    throw 'A dropped_iterations metric point is missing its timestamp, value, or scenario tag.'
                }
                $attempts.Add((
                    [ordered]@{
                        runId = $runId
                        type = 'droppedScheduledOperation'
                        scenario = $metric.data.tags.scenario
                        recordedAtUtc = $metric.data.time
                        count = $metric.data.value
                    } | ConvertTo-Json -Compress
                ))
            }
        }
    }

    if ($attempts.Count -gt 0) {
        Set-Content -LiteralPath $attemptsPath -Value $attempts.ToArray() -Encoding utf8
    }

    $summary = $null
    if (Test-Path -LiteralPath $summaryPath) {
        $summary = Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json
    }
    if ($exitCode -eq 0 -and ($null -eq $summary -or $attempts.Count -eq 0)) {
        $exitCode = 1
    }

    $measurementErrors = [System.Collections.Generic.List[string]]::new()
    $eventObjects = @(
        foreach ($eventLine in $attempts) {
            ConvertFrom-Json $eventLine
        }
    )
    $businessOperations = @($eventObjects | Where-Object {
        $_.type -eq 'businessOperation' -and $_.phase -eq $Phase
    })
    $canaryTicks = @($eventObjects | Where-Object { $_.type -eq 'canaryTick' })
    $droppedOperations = @($eventObjects | Where-Object {
        $_.type -eq 'droppedScheduledOperation'
    })
    $workloadDropped = @($droppedOperations | Where-Object { $_.scenario -eq 'workload' })
    $canaryDropped = @($droppedOperations | Where-Object { $_.scenario -eq 'canary' })
    $droppedWorkloadCount = [double](($workloadDropped | Measure-Object -Property count -Sum).Sum ?? 0)
    $droppedCanaryCount = [double](($canaryDropped | Measure-Object -Property count -Sum).Sum ?? 0)
    $businessOperationSuccesses = @($businessOperations | Where-Object { $_.success -eq $true }).Count
    $businessOperationFailures = @($businessOperations | Where-Object { $_.success -eq $false }).Count
    $businessOperationSuccessRate = $null
    $workloadAttemptFailureRate = $null
    $workloadAttemptSuccesses = $null
    $workloadAttemptFailures = $null
    $iterationCount = $null
    $successfulOperationP95Ms = $null

    if ($null -eq $summary) {
        $measurementErrors.Add('k6 did not produce a summary.')
    } else {
        $durationMetric = $summary.metrics.business_operation_duration
        if ($null -ne $durationMetric) {
            $durationValues = if ($durationMetric.PSObject.Properties['values']) { $durationMetric.values } else { $durationMetric }
            $successfulOperationP95Ms = $durationValues.'p(95)'
        } else {
            $measurementErrors.Add('k6 summary is missing successful-operation latency measurements.')
        }
        $workloadMetric = $summary.metrics.workload_attempt_success
        $droppedMetric = $summary.metrics.dropped_iterations
        $iterationMetric = $summary.metrics.iterations
        if ($null -eq $workloadMetric -or $null -eq $iterationMetric) {
            $measurementErrors.Add('k6 summary is missing required workload or iteration metrics.')
        } else {
            $workloadValues = if ($workloadMetric.PSObject.Properties['values']) { $workloadMetric.values } else { $workloadMetric }
            $iterationValues = if ($iterationMetric.PSObject.Properties['values']) { $iterationMetric.values } else { $iterationMetric }
            $workloadAttemptSuccesses = [double] $workloadValues.passes
            $workloadAttemptFailures = [double] $workloadValues.fails
            $summaryDroppedCount = 0.0
            if ($null -ne $droppedMetric) {
                $droppedValues = if ($droppedMetric.PSObject.Properties['values']) { $droppedMetric.values } else { $droppedMetric }
                $summaryDroppedCount = [double] $droppedValues.count
            }
            $iterationCount = [double] $iterationValues.count
            $recordedDroppedCount = $droppedWorkloadCount + $droppedCanaryCount

            if ($summaryDroppedCount -ne $recordedDroppedCount) {
                $measurementErrors.Add('Raw dropped-iteration events do not match the k6 summary count.')
            }
            if ($iterationCount -ne ($businessOperations.Count + $canaryTicks.Count)) {
                $measurementErrors.Add('Business-operation and canary event counts do not match the k6 iteration count.')
            }

            $attemptDenominator = $workloadAttemptSuccesses + $workloadAttemptFailures + $droppedWorkloadCount
            if ($attemptDenominator -gt 0) {
                $workloadAttemptFailureRate = (
                    $workloadAttemptFailures + $droppedWorkloadCount
                ) / $attemptDenominator
            } else {
                $measurementErrors.Add('No workload attempts or dropped workload operations were reported.')
            }

            $businessDenominator = $businessOperationSuccesses `
                + $businessOperationFailures `
                + $droppedWorkloadCount
            if ($businessDenominator -gt 0) {
                $businessOperationSuccessRate = $businessOperationSuccesses / $businessDenominator
                if ($businessOperationSuccessRate -lt $MinimumBusinessOperationSuccessRate) {
                    $exitCode = 1
                }
            } else {
                $measurementErrors.Add('No business operations or dropped workload operations were reported.')
            }
        }
    }

    if ($measurementErrors.Count -gt 0) {
        $exitCode = 1
    }
    $measurementError = if ($measurementErrors.Count -gt 0) {
        $measurementErrors -join ' '
    } else {
        $null
    }

    $endedAt = [DateTimeOffset]::UtcNow
    $report = [ordered]@{
        schemaVersion = 1
        runId = $runId
        phase = $Phase
        targetHost = $apiUri.Host
        startedAtUtc = $startedAt.ToString('O')
        endedAtUtc = $endedAt.ToString('O')
        durationSeconds = [Math]::Round(($endedAt - $startedAt).TotalSeconds, 3)
        configuredRatePerSecond = $Rate
        configuredDuration = $Duration
        minimumBusinessOperationSuccessRate = $MinimumBusinessOperationSuccessRate
        businessOperationSuccessRate = $businessOperationSuccessRate
        successfulBusinessOperations = $businessOperationSuccesses
        failedBusinessOperations = $businessOperationFailures
        workloadAttemptFailureRate = $workloadAttemptFailureRate
        workloadAttemptSuccesses = $workloadAttemptSuccesses
        workloadAttemptFailures = $workloadAttemptFailures
        droppedScheduledOperations = $droppedWorkloadCount
        droppedCanaryOperations = $droppedCanaryCount
        successfulCanaryTicks = @($canaryTicks | Where-Object { $_.success -eq $true }).Count
        failedCanaryTicks = @($canaryTicks | Where-Object { $_.success -eq $false }).Count
        k6Iterations = $iterationCount
        successfulOperationP95LimitMs = $SuccessfulOperationP95LimitMs
        successfulOperationP95Ms = $successfulOperationP95Ms
        attemptEventCount = $attempts.Count
        exitCode = $exitCode
        status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
        statusScope = 'Configured k6 successful-operation p95 and business-operation success threshold for this phase only; this is not an HA recovery verdict.'
        measurementError = $measurementError
        summaryFile = if ($summary) { 'summary.json' } else { $null }
        attemptsFile = if (Test-Path -LiteralPath $attemptsPath) { 'attempts.ndjson' } else { $null }
        metricsFile = if (Test-Path -LiteralPath $metricsPath) { 'metrics.ndjson' } else { $null }
    }
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding utf8

    if ($exitCode -ne 0) {
        throw "k6 failed with exit code $exitCode. See $runDirectory for sanitized run evidence."
    }

    Write-Output $runDirectory
}
finally {
    foreach ($name in $previousEnvironment.Keys) {
        if ($null -eq $previousEnvironment[$name]) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        } else {
            Set-Item -Path "Env:$name" -Value $previousEnvironment[$name]
        }
    }
}
