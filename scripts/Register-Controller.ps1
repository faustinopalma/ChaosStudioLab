[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [int] $TunnelPort = 50222,
    [switch] $AfterResume
)
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$m = Read-LabManifest $ManifestPath
if ($m.ContainsKey('lifecycle') -and $m.status -eq 'READY' -and -not $AfterResume) {
    Write-Output 'Existing ready timestamp and 24-hour suspension deadline are preserved.'
    return
}
$w = $m.outputs['csl-infrastructure'].workload.value
$o = $m.outputs['csl-infrastructure'].operations.value
$app = $m.outputs['csl-application']
$stateRoot = Split-Path $ManifestPath -Parent
$sshOptions = @(Get-LabSshOptions $m $stateRoot)
$sshArgs = $sshOptions + @('-p', [string]$TunnelPort, 'csloperator@127.0.0.1')
& ssh @sshArgs 'cd ~/csl && pwsh -NoLogo -NoProfile -File scripts/runner/test.ps1 -Phase warmup -Duration 60s > controller-baseline.log 2>&1'
if ($LASTEXITCODE -ne 0) { throw 'Private pre-controller baseline failed.' }
$revisions = Invoke-LabAz @('containerapp', 'revision', 'list', '-g', $script:LabGroups[1], '-n', 'ca-csl-api', '-o', 'json') | ConvertFrom-Json
$active = @($revisions | Where-Object { $_.properties.active })
if ($active.Count -ne 1) { throw 'Expected exactly one active app revision.' }
$readyAt = [DateTimeOffset]::UtcNow
$suspendAt = $readyAt.AddHours(24)
$scheduleRemainder = $suspendAt.Ticks % [TimeSpan]::TicksPerMinute
$suspensionScheduleAt = if ($scheduleRemainder) {
    $suspendAt.AddTicks([TimeSpan]::TicksPerMinute - $scheduleRemainder)
} else { $suspendAt }
$state = @{
    schemaVersion = 1; labId = $m.labId; deploymentInstanceId = $m.deploymentInstanceId
    desiredState = 'READY'; observedState = 'READY'; readyAtUtc = $readyAt.ToString('O')
    suspendAtUtc = $suspendAt.ToString('O'); updatedAtUtc = $readyAt.ToString('O')
    postgresId = $w.postgresId; runnerId = $o.runnerId; appId = $app.applicationId.value
    revisionId = $active[0].id
    environmentId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])/providers/Microsoft.App/managedEnvironments/cae-csl-workload"
    imageDigest = $m.imageDigest
}
Write-LabJson (Join-Path $stateRoot 'lifecycle.json') $state
Set-Content (Join-Path $stateRoot 'lifecycle-lock') 'Lab lifecycle lease anchor'
foreach ($name in @('lifecycle.json', 'lifecycle-lock')) {
    & scp @sshOptions -P $TunnelPort (Join-Path $stateRoot $name) "csloperator@127.0.0.1:csl/$name"
    if ($LASTEXITCODE -ne 0) { throw 'Lifecycle state transfer failed.' }
}
& ssh @sshArgs "cd ~/csl && az login --identity --client-id $($o.runnerClientId) --allow-no-subscriptions -o none && az account set --subscription $script:LabSubscription && az storage blob upload --account-name $($o.storageName) --container-name control-state --name lifecycle.json --file lifecycle.json --auth-mode login --overwrite -o none && az storage blob upload --account-name $($o.storageName) --container-name control-state --name lifecycle-lock --file lifecycle-lock --auth-mode login --overwrite -o none"
if ($LASTEXITCODE -ne 0) { throw 'Private identity-authenticated control state upload failed.' }
$aaId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[2])/providers/Microsoft.Automation/automationAccounts/$($o.automationName)"
$runbookId = "$aaId/runbooks/csl-lifecycle"
$runbook = @{
    location = $script:LabLocation
    properties = @{ runbookType = 'PowerShell'; runtimeEnvironment = 'csl-ps74'; logProgress = $false; logVerbose = $false; description = 'Exact-scope private lab lifecycle controller.'; draft = @{} }
}
$bodyPath = Join-Path $stateRoot 'controller-request.json'
try {
    Invoke-LabArm Put "https://management.azure.com$aaId/runtimeEnvironments/csl-ps74?api-version=2024-10-23" @{
        location = $script:LabLocation
        properties = @{ runtime = @{ language = 'PowerShell'; version = '7.4' }; defaultPackages = @{} }
    } | Out-Null
    Write-LabJson $bodyPath $runbook
    Invoke-LabAz @('rest', '--method', 'put', '--url', "https://management.azure.com${runbookId}?api-version=2024-10-23", '--body', "@$bodyPath", '-o', 'none') | Out-Null
    Invoke-LabAz @('rest', '--method', 'put', '--url', "https://management.azure.com$runbookId/draft/content?api-version=2023-11-01",
        '--headers', 'Content-Type=text/plain', '--body', "@$(Join-Path $PSScriptRoot 'runbooks\Lifecycle.ps1')", '-o', 'none') | Out-Null
    Invoke-LabAz @('rest', '--method', 'post', '--url', "https://management.azure.com$runbookId/publish?api-version=2023-11-01", '-o', 'none') | Out-Null
    $jobSchedules = @()
    $next = "https://management.azure.com$aaId/jobSchedules?api-version=2023-11-01"
    do {
        $page = Invoke-LabArm Get $next
        $jobSchedules += @($page.body.value)
        $next = if ($page.body.ContainsKey('nextLink')) { [string]$page.body.nextLink } else { $null }
    } while ($next)
    foreach ($entry in @(
        @{ name = 'csl-suspend-deadline'; properties = @{ startTime = $suspensionScheduleAt.ToString('O'); frequency = 'OneTime'; timeZone = 'UTC'; isEnabled = $true } },
        @{ name = 'csl-hourly-reconcile'; properties = @{ startTime = $readyAt.AddHours(1).ToString('O'); frequency = 'Hour'; interval = 1; timeZone = 'UTC'; isEnabled = $true } }
    )) {
        $scheduleId = "$aaId/schedules/$($entry.name)"
        Write-LabJson $bodyPath @{ properties = $entry.properties }
        Invoke-LabAz @('rest', '--method', 'put', '--url', "https://management.azure.com${scheduleId}?api-version=2023-11-01", '--body', "@$bodyPath", '-o', 'none') | Out-Null
        $bindingKey = "$($m.deploymentInstanceId)/csl-lifecycle-context-v1/$($entry.name)"
        $hash = [Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($bindingKey))
        $jobScheduleName = [Guid]::new([byte[]]$hash[0..15]).ToString()
        $jobScheduleId = "$aaId/jobSchedules/$jobScheduleName"
        $binding = @{ properties = @{
            schedule = @{ name = $entry.name }; runbook = @{ name = 'csl-lifecycle' }; runOn = $o.workerGroupName
            parameters = New-LabLifecycleParameters $o Reconcile
        } }
        $existing = @($jobSchedules | Where-Object {
            $_.properties.schedule.name -eq $entry.name -and $_.properties.runbook.name -eq 'csl-lifecycle'
        })
        if ($existing.Count) {
            if ($existing.Count -ne 1 -or
                $existing[0].id -notmatch "^$([Regex]::Escape($aaId))/jobSchedules/[0-9a-fA-F-]{36}$") {
                throw 'Lifecycle schedule association is ambiguous or outside the exact Automation account.'
            }
            Assert-LabResourceId $existing[0].id
            $properties = (Invoke-LabArm Get "https://management.azure.com$($existing[0].id)?api-version=2023-11-01").body.properties
            if ($properties.schedule.name -ne $entry.name -or
                $properties.runbook.name -ne 'csl-lifecycle' -or $properties.runOn -ne $o.workerGroupName -or
                $properties.parameters.Count -ne $binding.properties.parameters.Count) {
                throw 'Existing lifecycle schedule binding differs from the exact lab configuration.'
            }
            foreach ($parameter in $binding.properties.parameters.GetEnumerator()) {
                $keys = @($properties.parameters.Keys | Where-Object { $_ -ieq $parameter.Key })
                if ($keys.Count -ne 1 -or $properties.parameters[$keys[0]] -ne $parameter.Value) {
                    throw "Existing lifecycle schedule parameter differs: $($parameter.Key)"
                }
            }
        } else {
            Write-LabJson $bodyPath $binding
            Invoke-LabAz @('rest', '--method', 'put', '--url', "https://management.azure.com${jobScheduleId}?api-version=2023-11-01", '--body', "@$bodyPath", '-o', 'none') | Out-Null
        }
    }
    $verified = Invoke-LabAz @('rest', '--method', 'get', '--url', "https://management.azure.com$aaId/schedules/csl-suspend-deadline?api-version=2023-11-01", '-o', 'json') | ConvertFrom-Json
    $scheduledAt = [DateTimeOffset]$verified.properties.startTime
    $scheduleDelaySeconds = ($scheduledAt - $suspendAt).TotalSeconds
    if (-not $verified.properties.isEnabled -or $scheduledAt -ne $suspensionScheduleAt -or
        $scheduleDelaySeconds -lt 0 -or $scheduleDelaySeconds -ge 60) {
        throw 'Automatic suspension schedule must be the first full minute at or after the exact 24-hour deadline.'
    }
    $m.lifecycle = $state
    $m.status = 'READY'
    Save-LabInventory $m $ManifestPath
} finally { Remove-Item -LiteralPath $bodyPath -ErrorAction SilentlyContinue }
