$ErrorActionPreference = 'Stop'
$k6 = Get-Command k6 -ErrorAction Stop
$root = Join-Path ([IO.Path]::GetTempPath()) "csl-k6-format-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root | Out-Null
try {
    foreach ($mode in @('false', 'true')) {
        $summaryPath = Join-Path $root "$mode.summary.json"
        $metricsPath = Join-Path $root "$mode.metrics.ndjson"
        $consolePath = Join-Path $root "$mode.console.log"
        & $k6.Source run --log-format raw --env "DROP_SMOKE=$mode" --summary-export $summaryPath `
            --out "json=$metricsPath" (Join-Path $PSScriptRoot 'k6-format-smoke.js') *> $consolePath
        if ($LASTEXITCODE -ne 0) { throw 'Real k6 format smoke failed.' }
        $events = @(Get-Content $consolePath | Where-Object { $_ -match '^LAB_EVENT ' })
        if ($events.Count -eq 0) { throw 'Real k6 did not emit raw parseable event lines.' }
        foreach ($line in $events) { $line.Substring(10) | ConvertFrom-Json | Out-Null }
        $summary = Get-Content $summaryPath -Raw | ConvertFrom-Json
        if ($summary.metrics.iterations.count -ne $events.Count) { throw 'Real k6 iterations and raw events disagree.' }
        $drops = @(Get-Content $metricsPath | ForEach-Object { ConvertFrom-Json $_ } |
            Where-Object { $_.type -eq 'Point' -and $_.metric -eq 'dropped_iterations' })
        if ($mode -eq 'true') {
            $count = ($drops | Measure-Object -Property { $_.data.value } -Sum).Sum
            if ($count -le 0 -or $count -ne $summary.metrics.dropped_iterations.count) { throw 'Real k6 drops do not match summary counts.' }
            foreach ($drop in $drops) { if ($drop.data.tags.scenario -ne 'workload') { throw 'Real drop point lacks scenario targeting.' } }
        } elseif ($drops.Count -ne 0) { throw 'Zero-drop smoke unexpectedly dropped operations.' }
    }
    Write-Output 'Real k6 raw events, legacy summaries, zero-drop omission, and tagged drop points verified.'
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
