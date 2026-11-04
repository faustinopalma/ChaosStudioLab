[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ContextBase64
)
$ErrorActionPreference = 'Stop'
$context = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ContextBase64)) | ConvertFrom-Json -AsHashtable
if ($context.schemaVersion -ne 1) { throw 'Unsupported lifecycle context schema.' }
$StorageName = [string]$context.StorageName
$ControlClientId = [string]$context.ControlClientId
$SubscriptionId = [string]$context.SubscriptionId
$NetworkResourceGroupName = [string]$context.NetworkResourceGroupName
$WorkloadResourceGroupName = [string]$context.WorkloadResourceGroupName
$OperationsResourceGroupName = [string]$context.OperationsResourceGroupName
$Intent = [string]$context.Intent
if ($StorageName -notmatch '^[a-z0-9]{3,24}$' -or $ControlClientId -notmatch '^[0-9a-fA-F-]{36}$' -or
    $Intent -notin @('Reconcile', 'Suspend', 'Resume')) { throw 'Invalid lifecycle identity, storage or intent.' }
$subscription = $SubscriptionId
$groups = @($NetworkResourceGroupName, $WorkloadResourceGroupName, $OperationsResourceGroupName)
if ($subscription -notmatch '^[0-9a-fA-F-]{36}$' -or
    @($groups | Sort-Object -Unique).Count -ne 3 -or
    @($groups | Where-Object { $_ -notmatch '^rg-[a-zA-Z0-9._()-]{1,85}$' }).Count) {
    throw 'Invalid lifecycle subscription or exact resource-group scope.'
}
function Get-IdentityToken([string] $Resource) {
    $uri = 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=' +
        [Uri]::EscapeDataString($Resource) + '&client_id=' + [Uri]::EscapeDataString($ControlClientId)
    (Invoke-RestMethod $uri -Headers @{ Metadata = 'true' } -TimeoutSec 30).access_token
}
$armHeaders = @{ Authorization = "Bearer $(Get-IdentityToken 'https://management.azure.com/')" }
$blobHeaders = @{
    Authorization = "Bearer $(Get-IdentityToken 'https://storage.azure.com/')"
    'x-ms-version' = '2023-11-03'
}
$blobRoot = "https://$StorageName.blob.core.windows.net/control-state"
$leaseId = [Guid]::NewGuid().ToString()
$leaseHeaders = $blobHeaders.Clone()
$leaseHeaders['x-ms-lease-action'] = 'acquire'
$leaseHeaders['x-ms-lease-duration'] = '60'
$leaseHeaders['x-ms-proposed-lease-id'] = $leaseId
Invoke-WebRequest "$blobRoot/lifecycle-lock?comp=lease" -Method Put -Headers $leaseHeaders -TimeoutSec 30 | Out-Null
function Renew-Lock {
    $h = $blobHeaders.Clone()
    $h['x-ms-lease-action'] = 'renew'
    $h['x-ms-lease-id'] = $leaseId
    Invoke-WebRequest "$blobRoot/lifecycle-lock?comp=lease" -Method Put -Headers $h -TimeoutSec 30 | Out-Null
}
function Assert-Target([string] $Id) {
    foreach ($g in $groups) {
        if ($Id.StartsWith("/subscriptions/$subscription/resourceGroups/$g/providers/", [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    throw "Lifecycle target is outside the exact lab scope: $Id"
}
function Arm([string] $Method, [string] $Id, [string] $Version, [object] $Body = $null) {
    Assert-Target $Id
    Renew-Lock
    $uri = "https://management.azure.com${Id}?api-version=$Version"
    $args = @{ Uri = $uri; Method = $Method; Headers = $armHeaders; TimeoutSec = 60; ContentType = 'application/json' }
    if ($null -ne $Body) { $args.Body = ($Body | ConvertTo-Json -Depth 50) }
    Invoke-RestMethod @args
}
function Save-State {
    $h = $blobHeaders.Clone()
    $h['x-ms-blob-type'] = 'BlockBlob'
    $state.updatedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    Invoke-WebRequest "$blobRoot/lifecycle.json" -Method Put -Headers $h `
        -Body ($state | ConvertTo-Json -Depth 50) -ContentType 'application/json' -TimeoutSec 30 | Out-Null
}
function Wait-Postgres([string] $Expected) {
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(30)
    $previous = $null
    do {
        $pg = Arm Get $state.postgresId '2024-08-01'
        if ($pg.properties.state -ne $previous) {
            Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] PostgreSQL state: $($pg.properties.state); waiting for $Expected." -InformationAction Continue
            $previous = $pg.properties.state
        }
        if ($pg.properties.state -eq $Expected) { return $pg }
        Start-Sleep 20
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    throw "PostgreSQL did not reach $Expected before the deadline."
}
try {
    $state = Invoke-RestMethod "$blobRoot/lifecycle.json" -Headers $blobHeaders -TimeoutSec 30 |
        ConvertTo-Json -Depth 50 | ConvertFrom-Json -AsHashtable
    if ($state.schemaVersion -ne 1 -or $state.labId -ne 'lab-dev01' -or
        $state.deploymentInstanceId -notmatch '^[0-9a-f]{32}$') { throw 'Invalid lifecycle ownership state.' }
    foreach ($g in $groups) {
        $actual = Invoke-RestMethod "https://management.azure.com/subscriptions/$subscription/resourceGroups/${g}?api-version=2022-09-01" `
            -Headers $armHeaders -TimeoutSec 30
        if ($actual.tags.deploymentInstanceId -ne $state.deploymentInstanceId) { throw "Foreign group: $g" }
    }
    if ($state.desiredState -eq 'DESTROYING') { Write-Output 'Destroy is in progress; no lifecycle action taken.'; return }
    $now = [DateTimeOffset]::UtcNow
    if ($Intent -eq 'Reconcile') {
        if ($state.desiredState -eq 'RESUMING' -and [DateTimeOffset]::Parse($state.transitionExpiresUtc) -gt $now) {
            Write-Output 'Authorized resume is still within its transition deadline.'; return
        }
        if ($state.desiredState -eq 'SUSPENDED' -or $now -ge [DateTimeOffset]::Parse($state.suspendAtUtc)) {
            $Intent = 'Suspend'
        } else { Write-Output 'Lab is before its fixed suspension deadline.'; return }
    }
    if ($Intent -eq 'Suspend') {
        $state.desiredState = 'SUSPENDED'
        Save-State
        $revisions = Arm Get "$($state.appId)/revisions" '2024-03-01'
        foreach ($revision in $revisions.value | Where-Object { $_.properties.active }) {
            Arm Post "$($revision.id)/deactivate" '2024-03-01' | Out-Null
        }
        $pg = Arm Get $state.postgresId '2024-08-01'
        if ($pg.properties.state -ne 'Stopped') {
            if ($pg.properties.state -ne 'Ready') { $pg = Wait-Postgres Ready }
            Arm Post "$($state.postgresId)/stop" '2024-08-01' | Out-Null
            $pg = Wait-Postgres Stopped
        }
        Arm Patch $state.environmentId '2026-07-01' @{
            properties = @{ workloadProfiles = @(@{ name = 'D4'; workloadProfileType = 'D4'; minimumCount = 0; maximumCount = 3 }) }
        } | Out-Null
        Arm Post "$($state.runnerId)/deallocate" '2024-07-01' | Out-Null
        $state.observedState = 'SUSPENDED'
        $state.retainedResources = @('Operations NAT Gateway', 'Bastion', 'Hybrid Workers', 'Automation', 'Private endpoints', 'DNS', 'Storage', 'ACR', 'Key Vault', 'Monitoring')
        Save-State
        Write-Output 'Suspension completed; private lifecycle control is retained.'
    } else {
        $state.desiredState = 'RESUMING'
        $state.transitionExpiresUtc = $now.AddHours(1).ToString('O')
        Save-State
        Arm Post "$($state.runnerId)/start" '2024-07-01' | Out-Null
        $pg = Arm Get $state.postgresId '2024-08-01'
        if ($pg.properties.state -eq 'Stopped') { Arm Post "$($state.postgresId)/start" '2024-08-01' | Out-Null }
        $pg = Wait-Postgres Ready
        if ($pg.properties.highAvailability.mode -ne 'ZoneRedundant' -or
            $pg.properties.availabilityZone -eq $pg.properties.highAvailability.standbyAvailabilityZone) {
            throw 'Resume did not preserve distinct PostgreSQL HA zones.'
        }
        Arm Patch $state.environmentId '2026-07-01' @{
            properties = @{ workloadProfiles = @(@{ name = 'D4'; workloadProfileType = 'D4'; minimumCount = 3; maximumCount = 3 }) }
        } | Out-Null
        Arm Post "$($state.revisionId)/activate" '2024-03-01' | Out-Null
        $state.desiredState = 'VERIFYING_RESUME'
        $state.observedState = 'AWAITING_PRIVATE_BASELINE'
        Save-State
        Write-Output 'Resources resumed. Private baseline verification must succeed before arming a fresh 24-hour deadline.'
    }
} catch {
    if ($Intent -eq 'Resume' -and $null -ne $state) {
        $state.desiredState = 'SUSPENDED'
        $state.observedState = 'RESUME_FAILED_REQUIRES_RECONCILIATION'
        Save-State
    }
    throw
} finally {
    $release = $blobHeaders.Clone()
    $release['x-ms-lease-action'] = 'release'
    $release['x-ms-lease-id'] = $leaseId
    Invoke-WebRequest "$blobRoot/lifecycle-lock?comp=lease" -Method Put -Headers $release -TimeoutSec 30 | Out-Null
}
