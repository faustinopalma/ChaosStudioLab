[CmdletBinding()]
param([string] $AcknowledgedAttemptsPath, [switch] $VerifyAllRuns)
$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if ($LASTEXITCODE -ne 0) { throw 'Private verification identity login failed.' }
$token = & az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Private verification secret acquisition failed.' }
$base = "https://$($config.API_FQDN)"
$out = Join-Path $PSScriptRoot '..\..\results'
New-Item -ItemType Directory -Path $out -Force | Out-Null
$journal = Join-Path $out 'private-verification-writes.ndjson'
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
    $canonical = $payload | ConvertTo-Json -Compress
    $checksum = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
    $headers = @{ Authorization = "Bearer $token"; 'X-Run-Id' = 'private-smoke' }
    $unauthorized = Invoke-WebRequest "$base/api/orders/$operationId" -SkipHttpErrorCheck -TimeoutSec 15
    Assert-Proof 'Business endpoint requires authentication' ($unauthorized.StatusCode -eq 401) $unauthorized.StatusCode
    $first = $null
    $firstBody = $null
    $issuedAt = [DateTimeOffset]::UtcNow.ToString('O')
    try {
        $first = Invoke-WebRequest "$base/api/orders" -Method Post -Body $request -ContentType application/json -Headers $headers -SkipHttpErrorCheck -TimeoutSec 15
        if ($first.StatusCode -in @(200,201)) { $firstBody = $first.Content | ConvertFrom-Json }
    } finally {
        @{
            runId='private-verification';type='attempt';phase='private-verification';operation='write'
            operationId=$operationId;attempt=1;expectedChecksum=$checksum;recordedAtUtc=$issuedAt
            status=if ($null -ne $first) { $first.StatusCode } else { $null }
            acknowledged=$null -ne $first -and $first.StatusCode -in @(200,201)
            responseChecksum=if ($null -ne $firstBody) { $firstBody.payloadSha256 } else { $null }
            success=$null -ne $firstBody -and $firstBody.operationId -eq $operationId -and $firstBody.payloadSha256 -ceq $checksum
        } | ConvertTo-Json -Compress | Add-Content -LiteralPath $journal -Encoding utf8
    }
    Assert-Proof 'Durable create' ($first.StatusCode -eq 201) $first.StatusCode
    $second = Invoke-WebRequest "$base/api/orders" -Method Post -Body $request -ContentType application/json -Headers $headers -SkipHttpErrorCheck -TimeoutSec 15
    $secondBody = $second.Content | ConvertFrom-Json
    Assert-Proof 'Idempotent replay' ($second.StatusCode -eq 200 -and $firstBody.operationId -eq $secondBody.operationId -and $secondBody.payloadSha256 -ceq $checksum) $second.StatusCode
    $read = Invoke-RestMethod "$base/api/orders/$operationId" -Headers $headers -TimeoutSec 15
    Assert-Proof 'Read-after-write checksum' ($read.payloadSha256 -eq $checksum -and $read.operationId -eq $operationId) $read.payloadSha256
    $conflictRequest = @{ operationId = $operationId; payload = @{ sku = 'different'; quantity = 2; notes = 'durability-check' } } | ConvertTo-Json -Compress
    $conflict = Invoke-WebRequest "$base/api/orders" -Method Post -Body $conflictRequest -ContentType application/json -Headers $headers -SkipHttpErrorCheck -TimeoutSec 15
    Assert-Proof 'Different payload conflict' ($conflict.StatusCode -eq 409) $conflict.StatusCode
    $env:API_BASE_URL = $base
    $env:API_TOKEN = $token
    & (Join-Path $PSScriptRoot '..\..\tests\load\evaluate-durability.ps1') `
        -AttemptsPath $journal -OutputPath (Join-Path $out 'private-verification-durability.json')
    if ($LASTEXITCODE -ne 0) { throw 'Private verification write history was not fully reconciled.' }
    if ($AcknowledgedAttemptsPath) {
        $env:API_BASE_URL = $base
        $env:API_TOKEN = $token
        & (Join-Path $PSScriptRoot '..\..\tests\load\evaluate-durability.ps1') `
            -AttemptsPath $AcknowledgedAttemptsPath `
            -OutputPath (Join-Path (Split-Path $AcknowledgedAttemptsPath -Parent) 'durability-verdict.json')
    }
    if ($VerifyAllRuns) {
        $aggregate=@{status='INCONCLUSIVE';startedAtUtc=[DateTimeOffset]::UtcNow.ToString('O');runs=@()}
        try {
            foreach($directory in Get-ChildItem -LiteralPath $out -Directory | Sort-Object Name) {
                $attempts=Join-Path $directory.FullName 'attempts.ndjson'
                if(-not (Test-Path -LiteralPath $attempts)) { continue }
                if($directory.Name -notmatch '^[0-9a-f]{32}$') { throw 'Unexpected write-run directory; full-history reconciliation stopped.' }
                $verdictPath=Join-Path $directory.FullName 'durability-verdict.json'
                try {
                    & (Join-Path $PSScriptRoot '..\..\tests\load\evaluate-durability.ps1') -AttemptsPath $attempts -OutputPath $verdictPath
                } finally {
                    if(Test-Path -LiteralPath $verdictPath) {
                        $aggregate.runs+=@(Get-Content $verdictPath -Raw | ConvertFrom-Json)
                    }
                }
            }
            if($aggregate.runs.Count -eq 0) { throw 'Full-history verification found no measurement write runs.' }
            $aggregate.status='PASS'
        } finally {
            if(@($aggregate.runs | Where-Object status -eq 'FAIL').Count) { $aggregate.status='FAIL' }
            $aggregate.finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
            $aggregate | ConvertTo-Json -Depth 15 | Set-Content (Join-Path $out 'all-runs-durability.json') -Encoding utf8
        }
    }
} finally {
    $token = $null
    Remove-Item Env:\API_TOKEN -ErrorAction SilentlyContinue
    @{ recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O'); checks = $proofs.ToArray() } |
        ConvertTo-Json -Depth 10 | Set-Content (Join-Path $out 'private-verification.json') -Encoding utf8
}
