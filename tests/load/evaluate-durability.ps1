[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $AttemptsPath,
    [Parameter(Mandatory)][string] $OutputPath,
    [ValidateRange(0, 6)][int] $TransientReadRetries = 4
)
$ErrorActionPreference = 'Stop'
if (-not $env:API_BASE_URL -or -not $env:API_TOKEN) { throw 'Private API URL and token are required for durability verification.' }
$events = @(Get-Content -LiteralPath $AttemptsPath | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
$runIds = @($events | ForEach-Object runId | Sort-Object -Unique)
if ($runIds.Count -ne 1 -or -not $runIds[0]) { throw 'Durability evidence must contain exactly one run.' }
$writes = @{}
foreach ($event in $events | Where-Object { $_.type -eq 'attempt' -and $_.operation -eq 'write' }) {
    if ($event.operationId -notmatch '^[0-9a-fA-F-]{36}$' -or $event.expectedChecksum -notmatch '^[0-9a-f]{64}$') {
        throw 'Write evidence has an invalid operation ID or checksum.'
    }
    if (-not $writes.ContainsKey($event.operationId)) {
        $writes[$event.operationId] = @{ checksum = $event.expectedChecksum; acknowledged = $false }
    }
    $write = $writes[$event.operationId]
    if ($write.checksum -cne $event.expectedChecksum) { throw 'One logical write has inconsistent expected checksums.' }
    if ($event.status -in @(200, 201)) {
        if (-not $event.success -or $event.responseChecksum -cne $write.checksum) { throw 'An acknowledged write violated the response contract.' }
        $write.acknowledged = $true
    }
}
if ($writes.Count -eq 0) { throw 'No issued writes were found for durability verification.' }
$proof = [ordered]@{
    schemaVersion = 1; runId = $runIds[0]; status = 'INCONCLUSIVE'; verifiedAtUtc = $null
    issuedUniqueWrites = $writes.Count
    acknowledgedUniqueWrites = @($writes.Values | Where-Object acknowledged).Count
    retainedWrites = 0; confirmedAbsentUnacknowledgedWrites = 0; lostAcknowledgedWrites = 0
    transientReadRetries = 0; readsResolvedAfterRetry = 0
    failures = [Collections.Generic.List[object]]::new()
}
# A transient read-back response proves neither retention nor loss, so it is retried before the write is classified.
$transientStatuses = @(408, 429, 500, 502, 503, 504)
function Read-Write([string] $Id) {
    for ($attempt = 0; ; $attempt++) {
        try {
            $response = Invoke-WebRequest "$($env:API_BASE_URL.TrimEnd('/'))/api/orders/$Id" -Headers @{
                Authorization = "Bearer $env:API_TOKEN"; 'X-Run-Id' = $runIds[0]
            } -WebSession $session -SkipHttpErrorCheck -TimeoutSec 15
            if ($response.StatusCode -notin $transientStatuses -or $attempt -ge $TransientReadRetries) {
                if ($attempt -gt 0 -and $response.StatusCode -notin $transientStatuses) { $proof.readsResolvedAfterRetry++ }
                return $response
            }
        } catch {
            if ($attempt -ge $TransientReadRetries) { throw }
        }
        $proof.transientReadRetries++
        Start-Sleep -Seconds ([Math]::Pow(2, $attempt + 1))
    }
}
$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$processed = 0
try {
    foreach ($id in $writes.Keys) {
        $processed++
        if ($processed % 500 -eq 0) {
            Write-Information "Checking write $processed of $($writes.Count)." -InformationAction Continue
        }
        $write = $writes[$id]
        $response = Read-Write $id
        if ($response.StatusCode -eq 404 -and -not $write.acknowledged) {
            $proof.confirmedAbsentUnacknowledgedWrites++
            continue
        }
        if ($response.StatusCode -eq 200) {
            $body = $response.Content | ConvertFrom-Json
            if ($body.operationId -eq $id -and $body.payloadSha256 -ceq $write.checksum) {
                $proof.retainedWrites++
                continue
            }
        }
        if ($response.StatusCode -eq 404 -and $write.acknowledged) { $proof.lostAcknowledgedWrites++ }
        $proof.failures.Add(@{ operationId = $id; acknowledged = $write.acknowledged; httpStatus = $response.StatusCode })
    }
    $proof.status = if ($proof.failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
} finally {
    $session.Dispose()
    $proof.verifiedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
    $proof | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding utf8
}
if ($proof.status -ne 'PASS') { throw 'Durability verification found missing, changed or unresolved writes; inspect the saved verdict.' }
