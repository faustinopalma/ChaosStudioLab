$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) "csl-durability-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root | Out-Null
$oldUrl = $env:API_BASE_URL; $oldToken = $env:API_TOKEN
$env:API_BASE_URL = 'https://fixture.invalid'; $env:API_TOKEN = 'synthetic-token'
$checksum = 'a' * 64
$first = '00000000-0000-0000-0000-000000000001'
$second = '00000000-0000-0000-0000-000000000002'
function Invoke-WebRequest {
    param($Uri, $Headers, $WebSession, [switch]$SkipHttpErrorCheck, $TimeoutSec)
    if ($Headers.Authorization -ne 'Bearer synthetic-token') { throw 'Authentication header missing.' }
    if ($case -eq 'Transport') { throw 'Fixture transport error.' }
    $id = ($Uri -split '/')[-1]
    if ($id -eq $second -or $case -eq 'Lost') { return @{ StatusCode = 404; Content = '{}' } }
    @{ StatusCode = 200; Content = (@{
        operationId = $id; payloadSha256 = if ($case -eq 'Changed') { 'b' * 64 } else { $checksum }
    } | ConvertTo-Json -Compress) }
}
try {
    foreach ($case in @('Retained', 'Lost', 'Changed', 'Transport', 'Inconsistent')) {
        $ack = @{ runId = 'fixture'; type = 'attempt'; operation = 'write'; operationId = $first
            expectedChecksum = $checksum; responseChecksum = $checksum; status = 201; success = $true }
        $unack = @{ runId = 'fixture'; type = 'attempt'; operation = 'write'; operationId = $second
            expectedChecksum = $checksum; responseChecksum = $null; status = 503; success = $false }
        $retry = $ack.Clone()
        if ($case -eq 'Inconsistent') { $retry.expectedChecksum = 'c' * 64 }
        $inputFile = Join-Path $root "$case.ndjson"; $output = Join-Path $root "$case.json"
        @($ack, $retry, $unack) | ForEach-Object { $_ | ConvertTo-Json -Compress } | Set-Content $inputFile
        $rejected = $false
        try {
            & (Join-Path $PSScriptRoot 'evaluate-durability.ps1') -AttemptsPath $inputFile -OutputPath $output
        } catch { $rejected = $true }
        if ($rejected -ne ($case -ne 'Retained')) { throw "Durability verdict mismatch: $case." }
        if ($case -eq 'Inconsistent') { continue }
        $proof = Get-Content $output -Raw | ConvertFrom-Json
        if ($proof.issuedUniqueWrites -ne 2 -or $proof.acknowledgedUniqueWrites -ne 1) { throw 'Retries inflated unique write accounting.' }
        if ($case -eq 'Retained' -and ($proof.status -ne 'PASS' -or
            $proof.retainedWrites -ne 1 -or $proof.confirmedAbsentUnacknowledgedWrites -ne 1)) { throw 'Retained/absent reconciliation failed.' }
        if ($case -eq 'Lost' -and $proof.lostAcknowledgedWrites -ne 1) { throw 'Lost acknowledged write was not identified.' }
        if ($case -eq 'Transport' -and $proof.status -ne 'INCONCLUSIVE') { throw 'Transport failure produced a conclusive verdict.' }
    }
    'Durability verifies every unique issued write, exact checksums, absent unacknowledged writes, losses and explicit transport failures.'
} finally {
    $env:API_BASE_URL = $oldUrl; $env:API_TOKEN = $oldToken
    Remove-Item -LiteralPath $root -Recurse -Force
}
