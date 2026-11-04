[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [ValidateSet('warmup', 'baseline', 'failover')][string] $Phase = 'baseline',
    [int] $TunnelPort = 50222,
    [string] $Duration = '10m'
)
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$m = Read-LabManifest $ManifestPath
$stateRoot = Split-Path $ManifestPath -Parent
$evidenceRoot = Join-Path $stateRoot 'evidence'
New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
$w = $m.outputs['csl-infrastructure'].workload.value
$sshOptions = @(Get-LabSshOptions $m $stateRoot)
$sshArgs = $sshOptions + @('-p', [string]$TunnelPort, 'csloperator@127.0.0.1')
$lock = [IO.File]::Open("$ManifestPath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $pgBefore = Invoke-LabAz @('postgres', 'flexible-server', 'show', '-g', $script:LabGroups[1], '-n', $w.postgresName, '-o', 'json') | ConvertFrom-Json
    if ($pgBefore.highAvailability.mode -ne 'ZoneRedundant' -or
        $pgBefore.availabilityZone -eq $pgBefore.highAvailability.standbyAvailabilityZone -or
        $pgBefore.network.publicNetworkAccess -ne 'Disabled') { throw 'PostgreSQL private HA baseline failed.' }
    Write-LabJson (Join-Path $evidenceRoot "$Phase-postgres-before.json") $pgBefore
    $replicas = Invoke-LabAz @('containerapp', 'replica', 'list', '-g', $script:LabGroups[1], '-n', 'ca-csl-api', '-o', 'json') | ConvertFrom-Json
    Write-LabJson (Join-Path $evidenceRoot "$Phase-replicas.json") $replicas
    if (@($replicas).Count -lt 6) { throw 'Fewer than six app replicas are available before the test.' }
    $environment = Invoke-LabAz @('containerapp', 'env', 'show', '-g', $script:LabGroups[1], '-n', 'cae-csl-workload', '-o', 'json') | ConvertFrom-Json
    Write-LabJson (Join-Path $evidenceRoot "$Phase-environment.json") $environment
    if (-not $environment.properties.zoneRedundant -or $environment.properties.publicNetworkAccess -ne 'Disabled') {
        throw 'Container Apps zone redundancy or public access denial is not configured.'
    }
    $fqdn = $m.outputs['csl-application'].applicationFqdn.value
    $publicProbe = @{
        targetHost = $fqdn; recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        status = 'INCONCLUSIVE'; httpStatus = $null; error = $null
    }
    try {
        $internet = Invoke-WebRequest "https://$fqdn/health/live" -TimeoutSec 15 -SkipHttpErrorCheck
        $publicProbe.httpStatus = $internet.StatusCode
        $publicProbe.status = if ($internet.StatusCode -in @(403, 404)) { 'PASS' } else { 'FAIL' }
    } catch [System.Net.Http.HttpRequestException] {
        $publicProbe.status = 'PASS'
        $publicProbe.error = $_.Exception.Message
    } catch [System.Threading.Tasks.TaskCanceledException] {
        $publicProbe.status = 'PASS'
        $publicProbe.error = 'Public client timed out.'
    }
    Write-LabJson (Join-Path $evidenceRoot "$Phase-public-denial.json") $publicProbe
    if ($publicProbe.status -ne 'PASS') { throw 'The Internet access-denial probe did not pass.' }
    if ($Phase -eq 'failover') {
        $workspaceId = $w.chaosScenarioId -replace '/scenarios/[^/]+$', ''
        $workspace = Invoke-LabArm Get "https://management.azure.com${workspaceId}?api-version=2026-08-01-preview"
        $workloadScope = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])"
        if (@($workspace.body.properties.scopes).Count -ne 1 -or $workspace.body.properties.scopes[0] -ine $workloadScope) {
            throw 'Chaos resource discovery is not scoped to the exact owned workload group.'
        }
        $configuration = Invoke-LabArm Get "https://management.azure.com$($w.chaosScenarioId)/configurations/exact-lab-postgres?api-version=2026-08-01-preview"
        $targets = @($configuration.body.properties.resourceTargeting.include.resources)
        if ($targets.Count -ne 1 -or $targets[0] -ine $w.postgresId) {
            throw 'Chaos fault configuration is not restricted to the exact lab PostgreSQL server.'
        }
        $discovery = Invoke-LabArm Post "https://management.azure.com$workspaceId/discover?api-version=2026-08-01-preview"
        $discoveryUrl = [string]($discovery.headers.Location | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($discoveryUrl)) { throw 'Chaos discovery returned no polling target.' }
        $discoveryDeadline = [DateTimeOffset]::UtcNow.AddMinutes(15)
        do {
            Start-Sleep 15
            $discoveryResult = Invoke-LabArm Get $discoveryUrl
            Write-LabJson (Join-Path $evidenceRoot 'chaos-discovery.json') $discoveryResult.body
        } while ($discoveryResult.statusCode -ne 200 -and [DateTimeOffset]::UtcNow -lt $discoveryDeadline)
        if ($discoveryResult.statusCode -ne 200 -or $discoveryResult.body.properties.status -ne 'Succeeded') {
            throw "Chaos discovery failed or timed out: $($discoveryResult.body.properties.errors | ConvertTo-Json -Compress)"
        }
        $discoveredTargets = @()
        $discoveredPage = "https://management.azure.com$workspaceId/discoveredResources?api-version=2026-08-01-preview"
        $pageNumber = 0
        do {
            $page = Invoke-LabArm Get $discoveredPage
            Write-LabJson (Join-Path $evidenceRoot "chaos-discovered-resources-$pageNumber.json") $page.body
            $discoveredTargets += @($page.body.value | Where-Object { $_.properties.fullyQualifiedIdentifier -ieq $w.postgresId })
            $discoveredPage = if ($page.body.ContainsKey('nextLink')) { $page.body.nextLink } else { $null }
            $pageNumber++
        } while ($discoveredPage)
        if ($discoveredTargets.Count -ne 1) { throw 'Discovery did not expose exactly one matching lab PostgreSQL target; no load or fault was started.' }
        & ssh @sshArgs "cd ~/csl || exit 1; if test -f failover.pid && kill -0 `"`$(cat failover.pid)`" 2>/dev/null; then echo 'A prior failover workload is still running.' >&2; exit 1; fi; rm -f failover.exit; nohup sh -c 'pwsh -NoLogo -NoProfile -File scripts/runner/test.ps1 -Phase failover -Duration $Duration > failover.log 2>&1; echo `$? > failover.exit' </dev/null >/dev/null 2>&1 & echo `$! > failover.pid"
        if ($LASTEXITCODE -ne 0) { throw 'Private failover load startup failed.' }
        Start-Sleep 60
        & ssh @sshArgs 'cd ~/csl || exit 1; test ! -f failover.exit && kill -0 "$(cat failover.pid)"'
        if ($LASTEXITCODE -ne 0) { throw 'Private failover workload stopped before injection; no fault was submitted.' }
        $started = [DateTimeOffset]::UtcNow
        Assert-LabResourceId $w.chaosScenarioId
        $configurationId = "$($w.chaosScenarioId)/configurations/exact-lab-postgres"
        $actionResult = Invoke-LabArm Post "https://management.azure.com$configurationId/execute?api-version=2026-08-01-preview"
        Write-LabJson (Join-Path $evidenceRoot 'chaos-start-response.json') $actionResult
        $pollUrl = [string]($actionResult.headers.Location | Select-Object -First 1)
        if ([string]::IsNullOrWhiteSpace($pollUrl)) {
            if ($null -eq $actionResult.body -or -not $actionResult.body.ContainsKey('id')) { throw 'Chaos execute response has no polling target.' }
            $pollUrl = "https://management.azure.com$($actionResult.body.id)?api-version=2026-08-01-preview"
        }
        $m.activeChaosPollUrl = $pollUrl
        Write-LabJson $ManifestPath $m
        $deadline = $started.AddMinutes(15)
        $execution = $null
        do {
            Start-Sleep 15
            $executionResponse = Invoke-LabArm Get $pollUrl
            $execution = $executionResponse.body
            Write-LabJson (Join-Path $evidenceRoot 'chaos-executions.json') $execution
            $states = @($execution.properties.status)
        } while ($executionResponse.statusCode -ne 200 -and [DateTimeOffset]::UtcNow -lt $deadline)
        if ($executionResponse.statusCode -eq 200) {
            $m.activeChaosPollUrl = $null
            Write-LabJson $ManifestPath $m
        }
        if ($executionResponse.statusCode -ne 200 -or $execution.properties.status -ne 'Succeeded') {
            throw "Chaos execution failed or timed out: $($execution.properties.errors | ConvertTo-Json -Compress)"
        }
        $pgAfter = Invoke-LabAz @('postgres', 'flexible-server', 'show', '-g', $script:LabGroups[1], '-n', $w.postgresName, '-o', 'json') | ConvertFrom-Json
        Write-LabJson (Join-Path $evidenceRoot 'failover-postgres-after.json') $pgAfter
        $action = @($execution.properties.scenarioRunSummary | Where-Object { $_.state -eq 'Succeeded' }) | Select-Object -First 1
        $observedAt = if ($null -ne $action -and $action.startedAt) { $action.startedAt } else { $started.ToString('O') }
        $evidence = @{
            schemaVersion = 1; source = 'Azure Chaos Studio scenario execution and PostgreSQL control-plane zone observation'
            targetResourceId = $w.postgresId; actionSucceeded = ($states -contains 'Succeeded')
            observedAtUtc = $observedAt; noInterruption = $false
            primaryZoneBefore = $pgBefore.availabilityZone; primaryZoneAfter = $pgAfter.availabilityZone
            standbyZoneAfter = $pgAfter.highAvailability.standbyAvailabilityZone
        }
        if (@($execution.properties.resources).Count -ne 1 -or
            $execution.properties.resources[0].id -ine $w.postgresId) {
            throw 'Chaos execution evidence is not restricted to the exact lab PostgreSQL server.'
        }
        Write-LabJson (Join-Path $evidenceRoot 'failover-evidence.json') $evidence
        $loadDeadline = [DateTimeOffset]::UtcNow.AddMinutes(20)
        do {
            $done = & ssh @sshArgs 'test -f ~/csl/failover.exit && cat ~/csl/failover.exit || echo RUNNING'
            if ($LASTEXITCODE -ne 0) { throw 'Private failover completion probe failed; no completion verdict was inferred.' }
            if ($done -notcontains 'RUNNING') { break }
            Start-Sleep 20
        } while ([DateTimeOffset]::UtcNow -lt $loadDeadline)
        if ($done -contains 'RUNNING') { throw 'Private load test exceeded the bounded deadline.' }
    } else {
        & ssh @sshArgs "cd ~/csl && pwsh -NoLogo -NoProfile -File scripts/runner/test.ps1 -Phase $Phase -Duration $Duration > $Phase.log 2>&1"
        $phaseExit = $LASTEXITCODE
    }
    & ssh @sshArgs 'cd ~/csl && pwsh -NoLogo -NoProfile -File scripts/runner/telemetry.ps1 > telemetry.log 2>&1'
    $telemetryExit = $LASTEXITCODE
    Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase $Phase -TunnelPort $TunnelPort
    if ($telemetryExit -ne 0) { throw 'Private telemetry verification failed; evidence is saved.' }
    if ($Phase -eq 'failover') {
        $run = Get-ChildItem (Join-Path $evidenceRoot 'results') -Recurse -Filter run.json |
            ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json | Add-Member -NotePropertyName reportPath -NotePropertyValue $_.FullName -PassThru } |
            Where-Object { $_.phase -eq 'failover' } | Sort-Object startedAtUtc | Select-Object -Last 1
        if ($null -eq $run) { throw 'No failover phase report was produced.' }
        & (Join-Path $script:LabRoot 'tests\load\evaluate-recovery.ps1') `
            -AttemptsPath (Join-Path (Split-Path $run.reportPath -Parent) 'attempts.ndjson') `
            -FailoverEvidencePath (Join-Path $evidenceRoot 'failover-evidence.json') -WorkloadPhase failover `
            -OutputPath (Join-Path $evidenceRoot 'recovery-verdict.json')
        $verdict = Get-Content (Join-Path $evidenceRoot 'recovery-verdict.json') -Raw | ConvertFrom-Json
        if ($verdict.status -ne 'PASS' -or $verdict.recoveryDurationSeconds -gt 180) {
            throw 'Database failover recovery did not establish the required <=180-second recovery verdict.'
        }
        Test-LabDurability -ManifestPath $ManifestPath -RunId $run.runId -TunnelPort $TunnelPort -Phase failover
    } elseif ($phaseExit -ne 0) { throw "Private $Phase load acceptance failed; raw evidence has been saved." }
} catch {
    $failure = $_
    try {
        Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase $Phase -TunnelPort $TunnelPort -Partial
    } catch { Write-Warning "Partial runner evidence retrieval failed: $($_.Exception.Message)" }
    throw $failure
} finally { $lock.Dispose() }
