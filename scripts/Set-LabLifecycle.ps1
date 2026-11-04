[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][ValidateSet('Reconcile', 'Suspend', 'Resume')][string] $Intent,
    [int] $TunnelPort = 50222
)
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$m = Read-LabManifest $ManifestPath
if ($Intent -eq 'Resume') { Assert-LabPolicyExemptions $m }
$o = $m.outputs['csl-infrastructure'].operations.value
$aaId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[2])/providers/Microsoft.Automation/automationAccounts/$($o.automationName)"
$jobId = "$aaId/jobs/$([Guid]::NewGuid().ToString())"
$request = @{
    properties = @{
        runbook = @{ name = 'csl-lifecycle' }; runOn = $o.workerGroupName
        parameters = New-LabLifecycleParameters $o $Intent
    }
}
Invoke-LabArm Put "https://management.azure.com${jobId}?api-version=2023-11-01" $request | Out-Null
Write-LabJson (Join-Path (Split-Path $ManifestPath -Parent) "$Intent-request.json") @{
    jobId = $jobId; submittedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); intent = $Intent
}
$deadline = [DateTimeOffset]::UtcNow.AddMinutes(45)
$lastStatus = $null
do {
    Start-Sleep 15
    $job = Invoke-LabArm Get "https://management.azure.com${jobId}?api-version=2023-11-01"
    $status = $job.body.properties.status
    if ($status -ne $lastStatus) {
        Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Lifecycle $Intent job: $status." -InformationAction Continue
        $lastStatus = $status
    }
} while ($status -notin @('Completed', 'Failed', 'Stopped', 'Suspended') -and [DateTimeOffset]::UtcNow -lt $deadline)
Write-LabJson (Join-Path (Split-Path $ManifestPath -Parent) "$Intent-job.json") $job.body
if ($status -ne 'Completed') { throw "Private lifecycle job did not complete: $status" }
if ($Intent -in @('Suspend', 'Resume')) {
    $w = $m.outputs['csl-infrastructure'].workload.value
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(5)
    do {
        $postgres = Invoke-LabAz @('postgres', 'flexible-server', 'show', '-g', $script:LabGroups[1], '-n', $w.postgresName, '-o', 'json') | ConvertFrom-Json
        $runner = Invoke-LabAz @('vm', 'get-instance-view', '--ids', $o.runnerId, '-o', 'json') | ConvertFrom-Json
        $revisions = @(Invoke-LabAz @('containerapp', 'revision', 'list', '-g', $script:LabGroups[1], '-n', 'ca-csl-api', '-o', 'json') | ConvertFrom-Json)
        $environment = Invoke-LabAz @('containerapp', 'env', 'show', '-g', $script:LabGroups[1], '-n', 'cae-csl-workload', '-o', 'json') | ConvertFrom-Json
        $power = @($runner.instanceView.statuses | Where-Object { $_.code -like 'PowerState/*' } | ForEach-Object { $_.code })
        $active = @($revisions | Where-Object { $_.properties.active })
        $profile = @($environment.properties.workloadProfiles | Where-Object name -eq 'D4')
        $checks = @{
            postgres = $postgres.state -eq $(if ($Intent -eq 'Suspend') { 'Stopped' } else { 'Ready' }) -and
                ($Intent -eq 'Suspend' -or $postgres.highAvailability.state -eq 'Healthy')
            runner = @($power | Where-Object { $_ -eq $(if ($Intent -eq 'Suspend') { 'PowerState/deallocated' } else { 'PowerState/running' }) }).Count -eq 1
            revisions = $active.Count -eq $(if ($Intent -eq 'Suspend') { 0 } else { 1 }) -and
                ($Intent -eq 'Suspend' -or ($active[0].properties.healthState -eq 'Healthy' -and
                    $active[0].properties.provisioningState -eq 'Provisioned'))
            profile = $profile.Count -eq 1 -and $profile[0].minimumCount -eq $(if ($Intent -eq 'Suspend') { 0 } else { 3 })
        }
        Write-LabJson (Join-Path (Split-Path $ManifestPath -Parent) "$Intent-postconditions.json") @{
            recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); checks = $checks
            postgresState = $postgres.state; runnerPower = $power; activeRevisions = $active.Count
            postgresHaState = $postgres.highAvailability.state; activeRevisionStates = @($active | ForEach-Object { $_.properties })
            configuredProfiles = $environment.properties.workloadProfiles
        }
        if ($postgres.network.publicNetworkAccess -ne 'Disabled' -or
            $postgres.highAvailability.mode -ne 'ZoneRedundant' -or
            $postgres.availabilityZone -eq $postgres.highAvailability.standbyAvailabilityZone -or
            -not $environment.properties.zoneRedundant -or $environment.properties.publicNetworkAccess -ne 'Disabled') {
            throw 'Lifecycle changed private access or cross-zone HA invariants.'
        }
        if (@($checks.Values | Where-Object { -not $_ }).Count -eq 0) { break }
        if ([DateTimeOffset]::UtcNow -ge $deadline) { throw 'Completed lifecycle job did not reach its observed resource postconditions.' }
        Write-Information "Waiting for observed $Intent resource postconditions." -InformationAction Continue
        Start-Sleep 10
    } while ($true)
}
if ($Intent -eq 'Resume') {
    Wait-LabSsh $m (Split-Path $ManifestPath -Parent) $TunnelPort
    & (Join-Path $PSScriptRoot 'Register-Controller.ps1') -ManifestPath $ManifestPath -TunnelPort $TunnelPort -AfterResume
    $recoveryPath = Join-Path (Split-Path $ManifestPath -Parent) 'evidence\recovery-verdict.json'
    if (Test-Path -LiteralPath $recoveryPath) {
        $recovery = Get-Content $recoveryPath -Raw | ConvertFrom-Json
        Test-LabDurability -ManifestPath $ManifestPath -RunId $recovery.runId -TunnelPort $TunnelPort -Phase resume
    }
    Save-LabRunnerEvidence -ManifestPath $ManifestPath -Phase resume -TunnelPort $TunnelPort
} elseif ($Intent -eq 'Suspend') {
    $m.status = 'SUSPENDED'
    Write-LabJson $ManifestPath $m
}
