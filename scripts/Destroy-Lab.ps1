[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][string] $ManifestPath)
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$m = Read-LabManifest $ManifestPath
$lock = [IO.File]::Open("$ManifestPath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
try {
    Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Verifying exact ownership before cleanup." -InformationAction Continue
    $actual = @(Get-LabInventory $m)
    Assert-LabDestroyInventory $m $actual
    if (-not $PSCmdlet.ShouldProcess(($m.groups.name -join ', '), 'Delete the exact manifest-owned lab and purge its vault')) { return }
    $m.status = 'DESTROYING'
    Write-LabJson $ManifestPath $m
    $vaultIds = @($m.resourceIds | Where-Object { $_ -match '/providers/Microsoft.KeyVault/vaults/[^/]+$' })
    if ($m.ContainsKey('activeChaosPollUrl') -and $m.activeChaosPollUrl) {
        $runAddress = [Uri]$m.activeChaosPollUrl
        $cancelUrl = "https://management.azure.com$($runAddress.AbsolutePath)/cancel?api-version=2026-08-01-preview"
        Invoke-LabArm Post $cancelUrl | Out-Null
        $deadline = [DateTimeOffset]::UtcNow.AddMinutes(10)
        do {
            Start-Sleep 10
            $run = Invoke-LabArm Get $m.activeChaosPollUrl
        } while ($run.statusCode -ne 200 -and [DateTimeOffset]::UtcNow -lt $deadline)
        if ($run.statusCode -ne 200) { throw 'Active chaos run did not terminate before destruction.' }
    }
    if ($m.outputs.ContainsKey('csl-infrastructure')) {
        $w = $m.outputs['csl-infrastructure'].workload.value
        $o = $m.outputs['csl-infrastructure'].operations.value
        $scenarioId = $w.chaosScenarioId
        Assert-LabResourceId $scenarioId
        $operationsGroupExists = Invoke-LabAz @('group', 'exists', '-n', $script:LabGroups[2], '-o', 'tsv')
        if ($operationsGroupExists -eq 'true') {
            $aaId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[2])/providers/Microsoft.Automation/automationAccounts/$($o.automationName)"
            $schedules = Invoke-LabAz @('rest', '--method', 'get', '--url', "https://management.azure.com$aaId/schedules?api-version=2023-11-01", '-o', 'json') | ConvertFrom-Json
            foreach ($schedule in $schedules.value) {
                Invoke-LabArm Patch "https://management.azure.com$($schedule.id)?api-version=2023-11-01" @{
                    properties = @{ isEnabled = $false }
                } | Out-Null
            }
            $jobs = Invoke-LabAz @('rest', '--method', 'get', '--url', "https://management.azure.com$aaId/jobs?api-version=2023-11-01", '-o', 'json') | ConvertFrom-Json
            foreach ($job in $jobs.value | Where-Object { $_.properties.status -in @('Running', 'New', 'Activating', 'Queued') }) {
                Invoke-LabArm Post "https://management.azure.com$($job.id)/stop?api-version=2023-11-01" | Out-Null
            }
        }
    }
    foreach ($group in @($script:LabGroups[1], $script:LabGroups[2], $script:LabGroups[0])) {
        if ((Invoke-LabAz @('group', 'exists', '-n', $group, '-o', 'tsv')) -eq 'true') {
            Assert-LabDestroyInventory $m @(Get-LabInventory $m)
            Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Deleting $group; awaiting Azure resource-provider cleanup." -InformationAction Continue
            Invoke-LabAz @('group', 'delete', '-n', $group, '--yes', '-o', 'none') | Out-Null
            Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Group $group is absent." -InformationAction Continue
        }
    }
    $remaining = @(Get-LabInventory $m)
    if ($remaining.Count -gt 0) { throw 'Manifest-owned resources remain after deletion.' }
    $purge = 'NOT_CREATED'
    foreach ($vaultId in $vaultIds) {
        $vaultName = ($vaultId -split '/')[-1]
        $deleted = Invoke-LabAz @('keyvault', 'list-deleted', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json
        $ownedVault = @($deleted | Where-Object { $_.name -eq $vaultName -and $_.properties.vaultId -ieq $vaultId })
        if ($ownedVault.Count -eq 1) {
            Invoke-LabAz @('keyvault', 'purge', '-n', $vaultName, '-l', $script:LabLocation, '-o', 'none') | Out-Null
            $afterPurge = Invoke-LabAz @('keyvault', 'list-deleted', '--subscription', $script:LabSubscription, '-o', 'json') | ConvertFrom-Json
            if (@($afterPurge | Where-Object { $_.properties.vaultId -ieq $vaultId }).Count -gt 0) {
                throw 'The owned vault remains recoverable after purge.'
            }
            $purge = 'PURGED'
        } else { $purge = 'NO_RECOVERABLE_LAB_VAULT_FOUND' }
    }
    $baselinePath = Join-Path (Split-Path $ManifestPath -Parent) 'preexisting-resources.json'
    $externalChanges = $null
    if (Test-Path $baselinePath) {
        $baseline = Get-Content $baselinePath -Raw | ConvertFrom-Json -AsHashtable
        $current = Invoke-LabAz @('resource', 'list', '--subscription', $script:LabSubscription,
            '-o', 'json') | ConvertFrom-Json -AsHashtable
        $baselineIds = @($baseline | ForEach-Object { $_.id })
        $currentIds = @($current | ForEach-Object { $_.id })
        $externalChanges = @{
            missingPreexistingResourceIds = @($baselineIds | Where-Object { $_ -notin $currentIds })
            additionalResourceIds = @($currentIds | Where-Object { $_ -notin $baselineIds })
        }
    }
    $needsAttribution = $null -ne $externalChanges -and
        ($externalChanges.missingPreexistingResourceIds.Count -gt 0 -or $externalChanges.additionalResourceIds.Count -gt 0)
    $m.status = if ($needsAttribution) { 'DESTROYED_SCOPED_WITH_REMAINDER' } else { 'DESTROYED' }
    $m.cleanup = @{
        verifiedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        remainingCustomerControlledResourceIds = $remaining
        verifiedScope = 'The exact three dedicated lab groups only.'
        externalInventoryChanges = $externalChanges
        vaultPurge = $purge
        mandatoryRetention = 'Azure Activity Log, service billing/audit records and service-managed backup/deletion retention may remain.'
    }
    Write-LabJson $ManifestPath $m
    Write-Output 'All three exact lab groups are absent; customer-controlled lab deletion verified.'
    if ($needsAttribution) {
        Write-Warning 'Subscription inventory differs outside the deleted lab scope. External resources are retained for attribution; this is not a full subscription-cleanup verdict.'
    }
} finally { $lock.Dispose() }
