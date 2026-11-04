$ErrorActionPreference = 'Stop'

$pwsh = Get-Command 'pwsh' -ErrorAction Stop
$runnerPath = Join-Path $PSScriptRoot 'run.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    'csl-load-runner-' + [Guid]::NewGuid().ToString('N'))
$mockDirectory = Join-Path $testRoot 'bin'
$outputRoot = Join-Path $testRoot 'runs'
New-Item -ItemType Directory -Path $mockDirectory -Force | Out-Null

$mockK6 = @'
$summaryIndex = [Array]::IndexOf($args, '--summary-export')
$summaryPath = $args[$summaryIndex + 1]
$metricsArgument = $args | Where-Object { $_ -like 'json=*' } | Select-Object -First 1
$metricsPath = $metricsArgument.Substring(5)
$mode = $env:PHASE
$businessCount = if ($mode -eq 'baseline-dropped') { 119 } else { 120 }
$failedCount = if ($mode -eq 'baseline-fail') { 1 } else { 0 }
$droppedCount = if ($mode -eq 'baseline-dropped') { 1 } else { 0 }
$baseTime = [DateTimeOffset]::Parse('2026-01-01T00:00:00Z')

for ($index = 0; $index -lt $businessCount; $index++) {
    $success = -not ($mode -eq 'baseline-fail' -and $index -eq 0)
    $startedAt = $baseTime.AddMilliseconds($index * 50)
    $event = [ordered]@{
        runId = $env:RUN_ID
        type = 'businessOperation'
        phase = $mode
        operation = 'read'
        operationId = "synthetic-$index"
        startedAtUtc = $startedAt.ToString('O')
        completedAtUtc = $startedAt.AddMilliseconds(100).ToString('O')
        durationMs = 100
        success = $success
        outcome = if ($success) { 'completed' } else { 'failed' }
    }
    Write-Output ('INFO[0000] LAB_EVENT ' + ($event | ConvertTo-Json -Compress))
}

$canary = [ordered]@{
    runId = $env:RUN_ID
    type = 'canaryTick'
    phase = 'canary'
    scheduledAtUtc = $baseTime.ToString('O')
    recordedAtUtc = $baseTime.AddMilliseconds(10).ToString('O')
    durationMs = 20
    success = $true
}
Write-Output ('INFO[0000] LAB_EVENT ' + ($canary | ConvertTo-Json -Compress))

$summary = [ordered]@{
    metrics = [ordered]@{
        workload_attempt_success = @{
            values = @{
                passes = $businessCount - $failedCount
                fails = $failedCount
                rate = ($businessCount - $failedCount) / $businessCount
            }
        }
        dropped_iterations = @{ values = @{ count = $droppedCount } }
        iterations = @{ values = @{ count = $businessCount + 1 } }
        business_operation_duration = @{ values = @{ 'p(95)' = 100 } }
    }
}
if ($mode -eq 'baseline-legacy') {
    $summary.metrics.workload_attempt_success = $summary.metrics.workload_attempt_success.values
    $summary.metrics.iterations = $summary.metrics.iterations.values
    $summary.metrics.business_operation_duration = $summary.metrics.business_operation_duration.values
    $summary.metrics.Remove('dropped_iterations')
}
$summary | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $summaryPath -Encoding utf8

if ($droppedCount -gt 0) {
    $point = [ordered]@{
        type = 'Point'
        data = @{
            time = $baseTime.AddMilliseconds(500).ToString('O')
            value = $droppedCount
            tags = @{ scenario = 'workload' }
        }
        metric = 'dropped_iterations'
    }
    $point | ConvertTo-Json -Compress -Depth 10 | Set-Content -LiteralPath $metricsPath -Encoding utf8
} else {
    New-Item -ItemType File -Path $metricsPath -Force | Out-Null
}
exit 0
'@

$cmdShim = @'
@echo off
pwsh -NoLogo -NoProfile -File "%~dp0mock-k6.ps1" %*
exit /b %ERRORLEVEL%
'@
Set-Content -LiteralPath (Join-Path $mockDirectory 'mock-k6.ps1') -Value $mockK6 -Encoding utf8
Set-Content -LiteralPath (Join-Path $mockDirectory 'k6.cmd') -Value $cmdShim -Encoding ascii

$previousEnvironment = @{
    Path = $env:PATH
    ApiBaseUrl = $env:API_BASE_URL
    ApiToken = $env:API_TOKEN
}

try {
    $env:PATH = "$mockDirectory;$($previousEnvironment.Path)"
    $env:API_BASE_URL = 'https://private.example'
    $env:API_TOKEN = 'synthetic-test-token'

    $passDirectory = & $runnerPath -OutputRoot $outputRoot -Phase 'baseline' -Duration '1m'
    $passReport = Get-Content -LiteralPath (Join-Path $passDirectory 'run.json') -Raw |
        ConvertFrom-Json
    if ($passReport.status -ne 'PASS' -or
        $passReport.businessOperationSuccessRate -ne 1 -or
        $passReport.k6Iterations -ne 121) {
        throw 'A fully successful synthetic k6 run was not reported as PASS.'
    }

    $legacyDirectory = & $runnerPath -OutputRoot $outputRoot -Phase 'baseline-legacy' -Duration '1m'
    $legacyReport = Get-Content (Join-Path $legacyDirectory 'run.json') -Raw | ConvertFrom-Json
    if ($legacyReport.status -ne 'PASS' -or $legacyReport.droppedScheduledOperations -ne 0) {
        throw 'The real k6 legacy export shape without zero-drop metrics was not accepted.'
    }

    foreach ($phase in @('baseline-fail', 'baseline-dropped')) {
        try {
            & $runnerPath -OutputRoot $outputRoot -Phase $phase -Duration '1m' | Out-Null
            throw "Expected synthetic phase $phase to fail its acceptance threshold."
        } catch {
            if ($_.Exception.Message -like "Expected synthetic phase $phase*") {
                throw
            }
        }

        $runDirectory = Get-ChildItem -LiteralPath $outputRoot -Directory |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        $report = Get-Content -LiteralPath (Join-Path $runDirectory.FullName 'run.json') -Raw |
            ConvertFrom-Json
        if ($report.status -ne 'FAIL') {
            throw "Synthetic phase $phase was not reported as FAIL."
        }
        if ($phase -eq 'baseline-dropped' -and
            ($report.droppedScheduledOperations -ne 1 -or $report.measurementError)) {
            throw 'The dropped scheduled operation was not included in the measured denominator.'
        }
    }

    $tokenLeak = Get-ChildItem -LiteralPath $outputRoot -File -Recurse |
        Select-String -SimpleMatch $env:API_TOKEN -ErrorAction SilentlyContinue
    if ($tokenLeak) {
        throw 'The synthetic bearer token was written to a run artifact.'
    }

    Write-Output 'Load-runner synthetic PASS, FAIL, dropped-operation, and token-redaction tests passed.'
}
finally {
    foreach ($name in $previousEnvironment.Keys) {
        $environmentName = switch ($name) {
            'Path' { 'PATH' }
            'ApiBaseUrl' { 'API_BASE_URL' }
            'ApiToken' { 'API_TOKEN' }
        }
        if ($null -eq $previousEnvironment[$name]) {
            Remove-Item -Path "Env:$environmentName" -ErrorAction SilentlyContinue
        } else {
            Set-Item -Path "Env:$environmentName" -Value $previousEnvironment[$name]
        }
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
