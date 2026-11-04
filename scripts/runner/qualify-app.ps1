param(
    [ValidateRange(12,300)][int] $Samples = 120,
    [Parameter(Mandatory)][string] $OutputPath
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$config = Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
$journal = Join-Path $PSScriptRoot '..\..\results\private-verification-writes.ndjson'
if (-not (Test-Path -LiteralPath $journal)) { throw 'Run private bootstrap verification before instance participation qualification.' }
$seeds = @(Get-Content $journal | ForEach-Object { $_ | ConvertFrom-Json } | Where-Object acknowledged)
if ($seeds.Count -eq 0) { throw 'No acknowledged private verification write is available for read/checksum participation.' }
$seed = $seeds[-1]
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if ($LASTEXITCODE -ne 0) { throw 'Instance qualification identity login failed.' }
& az account set --subscription $config.SUBSCRIPTION_ID
if ($LASTEXITCODE -ne 0) { throw 'Instance qualification subscription selection failed.' }
$token = & az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw 'Instance qualification secret acquisition failed.' }
$observations = [Collections.Generic.List[object]]::new()
$dns = @{}
$started = [DateTimeOffset]::UtcNow
$deadline = $started.AddMinutes(5)
$failure = $null
try {
    foreach ($hostName in @($config.API_FQDN, $config.SCM_FQDN)) {
        $addresses = @([Net.Dns]::GetHostAddresses($hostName) | ForEach-Object IPAddressToString)
        $dns[$hostName] = $addresses
        if ($addresses.Count -eq 0 -or @($addresses | Where-Object { $_ -notlike '10.81.10.*' }).Count) {
            throw "Application/SCM DNS is outside the configured private endpoint subnet: $hostName"
        }
    }
    for ($sample = 0; $sample -lt $Samples; $sample++) {
        if ([DateTimeOffset]::UtcNow -ge $deadline) { throw 'Five-minute foreground instance qualification deadline expired.' }
        foreach ($kind in @('health','business')) {
            $url = if ($kind -eq 'health') { "https://$($config.API_FQDN)/health/live" }
                else { "https://$($config.API_FQDN)/api/orders/$($seed.operationId)" }
            $remaining = [int]($deadline-[DateTimeOffset]::UtcNow).TotalSeconds
            if ($remaining -lt 1) { throw 'Instance qualification deadline expired before the next request.' }
            $arguments = @{Uri=$url;TimeoutSec=[Math]::Min(10,$remaining);SkipHttpErrorCheck=$true
                Headers=@{Connection='close';'X-Run-Id'='instance-qualification'}}
            if ($kind -eq 'business') { $arguments.Headers.Authorization="Bearer $token" }
            $response = Invoke-WebRequest @arguments
            if ($response.StatusCode -ne 200) { throw "Instance participation $kind probe returned HTTP $($response.StatusCode)." }
            $body = $response.Content | ConvertFrom-Json
            $instance = [string]($response.Headers['X-Lab-Instance-Id'] | Select-Object -First 1)
            $processId = [string]($response.Headers['X-Lab-Process-Id'] | Select-Object -First 1)
            $processStart = [string]($response.Headers['X-Lab-Process-Start-Utc'] | Select-Object -First 1)
            if ([string]::IsNullOrWhiteSpace($instance) -or $processId -notmatch '^\d+$' -or
                [string]::IsNullOrWhiteSpace($processStart)) { throw 'Actual instance/process response headers are incomplete.' }
            if ($kind -eq 'health' -and ($body.status -ne 'live' -or $body.instanceId -ne $instance -or
                $body.processId -ne [int]$processId -or $body.revision -ne $config.SOURCE_REVISION)) {
                throw 'Actual health identity/process/source evidence is inconsistent.'
            }
            if ($kind -eq 'business' -and ($body.operationId -ne $seed.operationId -or $body.payloadSha256 -ne $seed.expectedChecksum)) {
                throw 'Authenticated business participation failed operation identity/checksum validation.'
            }
            $observations.Add(@{
                instanceId=$instance;processId=[int]$processId;processStartedAtUtc=$processStart
                status=if ($kind -eq 'health') { 'live' } else { 'business' }
                businessSuccess=$kind -eq 'business';observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
            })
        }
    }
} catch {
    $failure=$_.Exception.Message
    throw
} finally {
    $token=$null
    @{
        startedAtUtc=$started.ToString('O');finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        status=if ($null -eq $failure) { 'COLLECTED_REQUIRES_INVENTORY_GATE' } else { 'FAIL' }
        error=$failure;dns=$dns;readOperationId=$seed.operationId;expectedChecksum=$seed.expectedChecksum
        observations=$observations.ToArray()
    } | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $OutputPath -Encoding utf8
}
