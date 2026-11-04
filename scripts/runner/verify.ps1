param([string] $AcknowledgedAttemptsPath)
$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if ($LASTEXITCODE -ne 0) { throw 'Private verification identity login failed.' }
$token = & az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Private verification secret acquisition failed.' }
$base = "https://$($config.API_FQDN)"
$proofs = [System.Collections.Generic.List[object]]::new()
function Assert-Proof([string] $Name, [bool] $Pass, [object] $Detail) {
    $proofs.Add(@{ name = $Name; status = if ($Pass) { 'PASS' } else { 'FAIL' }; detail = $Detail })
    if (-not $Pass) { throw "Private verification failed: $Name" }
}
try {
    $addresses = [Net.Dns]::GetHostAddresses($config.API_FQDN) | ForEach-Object { $_.IPAddressToString }
    Assert-Proof 'Private endpoint DNS' (@($addresses).Count -gt 0 -and @($addresses | Where-Object { $_ -notlike '10.81.10.*' }).Count -eq 0) $addresses
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(10)
    do {
        $ready = Invoke-WebRequest "$base/health/ready" -SkipHttpErrorCheck -TimeoutSec 15
        if ($ready.StatusCode -eq 200) { break }
        Start-Sleep 10
    } while ([DateTimeOffset]::UtcNow -lt $deadline)
    Assert-Proof 'Private readiness' ($ready.StatusCode -eq 200) $ready.StatusCode
    $operationId = [Guid]::NewGuid().ToString()
    $payload = [ordered]@{ sku = 'private-smoke'; quantity = 2; notes = 'durability-check' }
    $request = @{ operationId = $operationId; payload = $payload } | ConvertTo-Json -Compress
    $headers = @{ Authorization = "Bearer $token"; 'X-Run-Id' = 'private-smoke' }
    $unauthorized = Invoke-WebRequest "$base/api/orders/$operationId" -SkipHttpErrorCheck -TimeoutSec 15
    Assert-Proof 'Business endpoint requires authentication' ($unauthorized.StatusCode -eq 401) $unauthorized.StatusCode
    $first = Invoke-WebRequest "$base/api/orders" -Method Post -Body $request -ContentType application/json -Headers $headers -SkipHttpErrorCheck -TimeoutSec 15
    $firstBody = $first.Content | ConvertFrom-Json
    Assert-Proof 'Durable create' ($first.StatusCode -eq 201) $first.StatusCode
    $second = Invoke-WebRequest "$base/api/orders" -Method Post -Body $request -ContentType application/json -Headers $headers -SkipHttpErrorCheck -TimeoutSec 15
    $secondBody = $second.Content | ConvertFrom-Json
    Assert-Proof 'Idempotent replay' ($second.StatusCode -eq 200 -and $firstBody.operationId -eq $secondBody.operationId) $second.StatusCode
    $read = Invoke-RestMethod "$base/api/orders/$operationId" -Headers $headers -TimeoutSec 15
    $canonical = $payload | ConvertTo-Json -Compress
    $checksum = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
    Assert-Proof 'Read-after-write checksum' ($read.payloadSha256 -eq $checksum -and $read.operationId -eq $operationId) $read.payloadSha256
    $conflictRequest = @{ operationId = $operationId; payload = @{ sku = 'different'; quantity = 2; notes = 'durability-check' } } | ConvertTo-Json -Compress
    $conflict = Invoke-WebRequest "$base/api/orders" -Method Post -Body $conflictRequest -ContentType application/json -Headers $headers -SkipHttpErrorCheck -TimeoutSec 15
    Assert-Proof 'Different payload conflict' ($conflict.StatusCode -eq 409) $conflict.StatusCode
    if ($AcknowledgedAttemptsPath) {
        $env:API_BASE_URL = $base
        $env:API_TOKEN = $token
        & (Join-Path $PSScriptRoot '..\..\tests\load\evaluate-durability.ps1') `
            -AttemptsPath $AcknowledgedAttemptsPath `
            -OutputPath (Join-Path (Split-Path $AcknowledgedAttemptsPath -Parent) 'durability-verdict.json')
    }
} finally {
    $token = $null
    Remove-Item Env:\API_TOKEN -ErrorAction SilentlyContinue
    $out = Join-Path $PSScriptRoot '..\..\results'
    New-Item -ItemType Directory -Path $out -Force | Out-Null
    @{ recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); checks = $proofs.ToArray() } |
        ConvertTo-Json -Depth 10 | Set-Content (Join-Path $out 'private-verification.json') -Encoding utf8
}
