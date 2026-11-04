[CmdletBinding()]
param(
    [ValidateSet('warmup', 'baseline', 'failover')]
    [string] $Phase = 'baseline',
    [string] $Duration = '10m'
)
$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
$env:API_BASE_URL = "https://$($config.API_FQDN)"
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions --output none
if ($LASTEXITCODE -ne 0) { throw 'Runner managed identity login failed.' }
$env:API_TOKEN = & az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($env:API_TOKEN)) { throw 'Private secret retrieval failed.' }
$leaseJob = $null
$leaseId = $null
$storageToken = $null
try {
    $exists = & az storage blob exists --account-name $config.STORAGE_NAME --container-name control-state `
        --name lifecycle-lock --auth-mode login --query exists -o tsv
    if ($LASTEXITCODE -ne 0) { throw 'Private lifecycle lock lookup failed.' }
    if ($exists -eq 'true') {
        $storageToken = & az account get-access-token --resource https://storage.azure.com/ --query accessToken -o tsv
        if ($LASTEXITCODE -ne 0) { throw 'Storage identity token acquisition failed.' }
        $leaseId = [Guid]::NewGuid().ToString()
        $leaseUrl = "https://$($config.STORAGE_NAME).blob.core.windows.net/control-state/lifecycle-lock?comp=lease"
        $headers = @{
            Authorization = "Bearer $storageToken"; 'x-ms-version' = '2023-11-03'
            'x-ms-lease-action' = 'acquire'; 'x-ms-lease-duration' = '60'; 'x-ms-proposed-lease-id' = $leaseId
        }
        Invoke-WebRequest $leaseUrl -Method Put -Headers $headers -TimeoutSec 30 | Out-Null
        $leaseJob = Start-ThreadJob -ScriptBlock {
            param($Url, $Token, $Lease)
            $ErrorActionPreference = 'Stop'
            while ($true) {
                Start-Sleep 20
                Invoke-WebRequest $Url -Method Put -Headers @{
                    Authorization = "Bearer $Token"; 'x-ms-version' = '2023-11-03'
                    'x-ms-lease-action' = 'renew'; 'x-ms-lease-id' = $Lease
                } -TimeoutSec 30 | Out-Null
            }
        } -ArgumentList $leaseUrl, $storageToken, $leaseId
    }
    $ready = Invoke-RestMethod "$($env:API_BASE_URL)/health/ready"
    if ($ready.status -ne 'ready') { throw 'API private readiness check failed.' }
    & (Join-Path $PSScriptRoot '..\..\tests\load\run.ps1') `
        -OutputRoot (Join-Path $PSScriptRoot '..\..\results') -Phase $Phase -Duration $Duration
    if ($null -ne $leaseJob -and $leaseJob.State -eq 'Failed') { Receive-Job $leaseJob -ErrorAction Stop }
} finally {
    if ($null -ne $leaseJob) { Stop-Job $leaseJob; Remove-Job $leaseJob }
    if ($null -ne $leaseId) {
        Invoke-WebRequest $leaseUrl -Method Put -Headers @{
            Authorization = "Bearer $storageToken"; 'x-ms-version' = '2023-11-03'
            'x-ms-lease-action' = 'release'; 'x-ms-lease-id' = $leaseId
        } -TimeoutSec 30 | Out-Null
    }
    $storageToken = $null
    Remove-Item Env:\API_TOKEN -ErrorAction SilentlyContinue
}
