$ErrorActionPreference = 'Stop'

$pwsh = Get-Command 'pwsh' -ErrorAction Stop
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'csl-recovery-evaluator-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$evaluatorPath = Join-Path $PSScriptRoot 'evaluate-recovery.ps1'
$evidencePath = Join-Path $testRoot 'evidence.json'
$baseTime = [DateTimeOffset]::Parse('2026-01-01T00:00:00Z')

function New-SyntheticEvents([bool] $FailCanary, [TimeSpan] $TimestampOffset) {
    $events = [System.Collections.Generic.List[string]]::new()
    for ($second = 0; $second -lt 120; $second++) {
        $time = $baseTime.AddSeconds($second).ToOffset($TimestampOffset)
        $canarySuccess = -not $FailCanary
        $events.Add((
            [ordered]@{
                runId = 'synthetic-run'
                type = 'canaryTick'
                scheduledAtUtc = $time.ToString('O')
                recordedAtUtc = $time.AddMilliseconds(10).ToString('O')
                durationMs = 20
                success = $canarySuccess
            } | ConvertTo-Json -Compress
        ))

        if ($second -eq 0) {
            $events.Add((
                [ordered]@{
                    runId = 'synthetic-run'
                    type = 'droppedScheduledOperation'
                    scenario = 'workload'
                    recordedAtUtc = $time.AddMilliseconds(5).ToString('O')
                    count = 1
                } | ConvertTo-Json -Compress
            ))
        }

        $operationsThisSecond = if ($second -eq 0) { 19 } else { 20 }
        for ($operation = 0; $operation -lt $operationsThisSecond; $operation++) {
            $success = -not ($second -lt 11 -and $operation -eq 0)
            $startedAt = $time.AddMilliseconds($operation * 40)
            $events.Add((
                [ordered]@{
                    runId = 'synthetic-run'
                    type = 'businessOperation'
                    phase = 'database-failover'
                    operation = 'read'
                    operationId = "$second-$operation"
                    startedAtUtc = $startedAt.ToString('O')
                    completedAtUtc = $startedAt.AddMilliseconds(450).ToString('O')
                    durationMs = 450
                    success = $success
                    outcome = if ($success) { 'completed' } else { 'failed' }
                } | ConvertTo-Json -Compress
            ))
        }
    }
    return $events
}

function Invoke-EvaluatorCase(
    [string] $Name,
    [bool] $FailCanary,
    [bool] $NoInterruption,
    [string] $ExpectedStatus,
    [int] $ExpectedExitCode,
    [TimeSpan] $TimestampOffset = [TimeSpan]::Zero,
    [double] $EvidenceOffsetSeconds = 0,
    [double] $ExpectedRecoverySeconds = -1
) {
    $caseRoot = Join-Path $testRoot $Name
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    $caseAttempts = Join-Path $caseRoot 'attempts.ndjson'
    $caseReport = Join-Path $caseRoot 'report.json'
    $caseEvidence = [ordered]@{
        schemaVersion = 1
        source = 'synthetic-independent-event'
        targetResourceId = '/subscriptions/test/resourceGroups/test/providers/test/resource'
        actionSucceeded = $true
        observedAtUtc = $baseTime.AddSeconds($EvidenceOffsetSeconds).ToOffset($TimestampOffset).ToString('O')
        noInterruption = $NoInterruption
    }

    Set-Content -LiteralPath $caseAttempts -Value (New-SyntheticEvents $FailCanary $TimestampOffset) -Encoding utf8
    $caseEvidence | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $evidencePath -Encoding utf8
    & $pwsh.Source -NoProfile -File $evaluatorPath `
        -AttemptsPath $caseAttempts `
        -FailoverEvidencePath $evidencePath `
        -WorkloadPhase 'database-failover' `
        -OutputPath $caseReport | Out-Null
    $exitCode = $LASTEXITCODE
    $report = Get-Content -LiteralPath $caseReport -Raw | ConvertFrom-Json

    if ($exitCode -ne $ExpectedExitCode -or $report.status -ne $ExpectedStatus) {
        throw "$Name expected $ExpectedStatus/exit $ExpectedExitCode; received $($report.status)/exit $exitCode."
    }
    if ($Name -eq 'exact-99-percent' -and
        [Math]::Abs($report.qualifyingWindow.businessOperationSuccessRate - 0.99) -gt 0.000001) {
        throw 'The evaluator did not preserve the exact 99% threshold boundary.'
    }
    if ($Name -eq 'exact-99-percent' -and
        $report.qualifyingWindow.droppedScheduledOperations -ne 1) {
        throw 'Dropped scheduled operations were not included in the business denominator.'
    }
    if ($ExpectedRecoverySeconds -ge 0 -and
        [Math]::Abs($report.recoveryDurationSeconds - $ExpectedRecoverySeconds) -gt 0.000001) {
        throw "$Name did not preserve the UTC instant and fractional-second recovery duration."
    }
}

try {
    Invoke-EvaluatorCase 'exact-99-percent' $false $true 'PASS' 0
    Invoke-EvaluatorCase 'zero-duration-without-proof' $false $false 'INCONCLUSIVE' 2
    Invoke-EvaluatorCase 'canary-outage' $true $false 'FAIL' 1
    Invoke-EvaluatorCase 'positive-offset' $false $true 'PASS' 0 ([TimeSpan]::FromHours(1)) 0 0
    Invoke-EvaluatorCase 'negative-offset' $false $true 'PASS' 0 ([TimeSpan]::FromHours(-7)) 0 0
    Invoke-EvaluatorCase 'fractional-offset' $false $false 'PASS' 0 ([TimeSpan]::FromHours(5.5)) 0.3762627 0.624
    Write-Output 'Recovery evaluator PASS, FAIL, INCONCLUSIVE, threshold, timezone and fractional-second cases passed.'
}
finally {
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
