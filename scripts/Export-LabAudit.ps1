[CmdletBinding()]
param([Parameter(Mandatory)][string] $ManifestPath)
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$m = Read-LabManifest $ManifestPath
$stateRoot = Split-Path $ManifestPath -Parent
$events = Invoke-LabAz @('monitor', 'activity-log', 'list', '--subscription', $script:LabSubscription,
    '--start-time', $m.createdAtUtc, '--max-events', '1000', '-o', 'json') | ConvertFrom-Json
$records = @($events | Where-Object { $_.operationName.value -match '/(write|delete|action)$' } |
    ForEach-Object {
        $inside = $false
        foreach ($g in $script:LabGroups) {
            $prefix = "/subscriptions/$script:LabSubscription/resourceGroups/$g"
            if ($_.resourceId -ieq $prefix -or $_.resourceId.StartsWith("$prefix/", [StringComparison]::OrdinalIgnoreCase)) { $inside = $true }
        }
        @{
            recordedAtUtc = $_.eventTimestamp; operation = $_.operationName.value
            resourceId = $_.resourceId; status = $_.status.value; caller = $_.caller
            insideDedicatedLabGroups = $inside
        }
    })
Write-LabJson (Join-Path $stateRoot 'activity-mutation-audit.json') $records
Write-Output 'Activity audit exported. Service-managed operations and unrelated callers require separate attribution.'
