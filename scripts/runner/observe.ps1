param(
    [Parameter(Mandatory)][ValidatePattern('^[0-9a-f]{32}$')][string] $RunId,
    [Parameter(Mandatory)][ValidateRange(60,1800)][int] $Seconds
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$config=Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
$directory=Join-Path $PSScriptRoot "..\..\results\observer-$RunId"
if(Test-Path -LiteralPath $directory) { throw 'Observer evidence must use a fresh, attributable run ID.' }
New-Item -ItemType Directory -Path $directory | Out-Null
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if($LASTEXITCODE -ne 0) { throw 'Private observer identity login failed.' }
$token=& az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) { throw 'Private observer secret acquisition failed.' }
$started=[DateTimeOffset]::UtcNow
$deadline=$started.AddSeconds($Seconds)
$path=Join-Path $directory 'observations.ndjson'
try {
    while([DateTimeOffset]::UtcNow -lt $deadline) {
        foreach($kind in @('live','dependencies')) {
            $remaining=[int]($deadline-[DateTimeOffset]::UtcNow).TotalSeconds
            if($remaining -lt 1) { break }
            $event=[ordered]@{
                runId=$RunId;kind=$kind;requestedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
                observedAtUtc=$null;statusCode=$null;instanceId=$null;processId=$null;processStartedAtUtc=$null
                dependencyStatus=$null;error=$null
            }
            try {
                $response=Invoke-WebRequest "https://$($config.API_FQDN)/health/$kind" `
                    -Headers @{Authorization="Bearer $token";Connection='close';'X-Run-Id'="observer-$RunId"} `
                    -SkipHttpErrorCheck -TimeoutSec ([Math]::Min(5,$remaining))
                $event.statusCode=$response.StatusCode
                $event.instanceId=[string]($response.Headers['X-Lab-Instance-Id'] | Select-Object -First 1)
                $event.processId=[string]($response.Headers['X-Lab-Process-Id'] | Select-Object -First 1)
                $event.processStartedAtUtc=[string]($response.Headers['X-Lab-Process-Start-Utc'] | Select-Object -First 1)
                if($kind -eq 'dependencies' -and $response.StatusCode -in @(200,503)) {
                    if([string]($response.Headers['Content-Type'] | Select-Object -First 1) -like 'application/json*') {
                        $body=$response.Content | ConvertFrom-Json
                        $event.dependencyStatus=$body.dependencies.postgresql
                    } else {
                        $event.error="HTTP $($response.StatusCode) returned a non-JSON response; PostgreSQL dependency status is unverified."
                    }
                }
            } catch [Net.Http.HttpRequestException], [Net.WebException], [Threading.Tasks.TaskCanceledException] {
                $event.statusCode=0
                $event.error=$_.Exception.Message
            } finally {
                $event.observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
                $event | ConvertTo-Json -Compress | Add-Content -LiteralPath $path -Encoding utf8
            }
        }
        Start-Sleep -Seconds 1
    }
} finally {
    $token=$null
    @{runId=$RunId;startedAtUtc=$started.ToString('O');finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')} |
        ConvertTo-Json | Set-Content (Join-Path $directory 'completed.json') -Encoding utf8
}
