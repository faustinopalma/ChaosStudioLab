[CmdletBinding()]
param(
    [ValidateSet('warmup', 'baseline', 'app-instance', 'app-zone', 'failover', 'combined')]
    [string] $Phase = 'baseline',
    [ValidatePattern('^\d+[sm]$')][string] $Duration = '10m',
    [ValidatePattern('^[0-9a-f]{32}$')][string] $RunId = [Guid]::NewGuid().ToString('N')
)
$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
$env:API_BASE_URL = "https://$($config.API_FQDN)"
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions --output none
if ($LASTEXITCODE -ne 0) { throw 'Runner managed identity login failed.' }
$env:API_TOKEN = & az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($env:API_TOKEN)) { throw 'Private secret retrieval failed.' }
try {
    $ready = Invoke-RestMethod "$($env:API_BASE_URL)/health/ready" -TimeoutSec 10
    if ($ready.status -ne 'ready') { throw 'Private readiness check failed before the load phase.' }
    $rate = if ($Phase -in @('app-instance', 'app-zone')) { 0.99 } else { 0.999 }
    $p95 = if ($Phase -in @('app-instance', 'app-zone')) { 2000 } else { 1000 }
    & (Join-Path $PSScriptRoot '..\..\tests\load\run.ps1') `
        -OutputRoot (Join-Path $PSScriptRoot '..\..\results') -Phase $Phase -Duration $Duration -RunId $RunId `
        -MinimumBusinessOperationSuccessRate $rate -SuccessfulOperationP95LimitMs $p95
} finally { Remove-Item Env:\API_TOKEN -ErrorAction SilentlyContinue }
