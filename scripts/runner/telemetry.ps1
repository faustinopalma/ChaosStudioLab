$ErrorActionPreference = 'Stop'
$config = Get-Content (Join-Path $PSScriptRoot '..\..\runner-config.json') -Raw | ConvertFrom-Json
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if ($LASTEXITCODE -ne 0) { throw 'Telemetry runner identity login failed.' }
$token = & az account get-access-token --resource https://api.loganalytics.io --query accessToken -o tsv
if ($LASTEXITCODE -ne 0) { throw 'Private query token acquisition failed.' }
try {
    $body = @{
        query = "union withsource=SourceTable isfuzzy=true AppRequests, AppServiceConsoleLogs, AppServicePlatformLogs | where TimeGenerated > ago(1h) | summarize Records=count() by SourceTable"
        timespan = 'PT1H'
    } | ConvertTo-Json -Compress
    $uri = "https://api.loganalytics.io/v1/workspaces/$($config.LOG_ANALYTICS_WORKSPACE_ID)/query"
    $result = Invoke-RestMethod $uri -Method Post -Headers @{ Authorization = "Bearer $token" } -Body $body -ContentType application/json -TimeoutSec 60
    $rows = @($result.tables[0].rows)
    $recordCount = 0
    $appRequests = 0
    $systemLogs = 0
    foreach ($row in $rows) {
        $recordCount += [int]$row[1]
        if ($row[0] -eq 'AppRequests') { $appRequests += [int]$row[1] }
        if ($row[0] -eq 'AppServicePlatformLogs') { $systemLogs += [int]$row[1] }
    }
    $report = @{
        recordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        status = if ($appRequests -gt 0 -and $systemLogs -gt 0) { 'PASS' } else { 'INCONCLUSIVE' }
        queryHost = 'api.loganalytics.io'; records = $recordCount; response = $result
        applicationRequests = $appRequests; appServicePlatformLogs = $systemLogs
    }
    $out = Join-Path $PSScriptRoot '..\..\results'
    $report | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $out 'private-telemetry.json') -Encoding utf8
    if ($appRequests -eq 0 -or $systemLogs -eq 0) { throw 'Private application-request and App Service platform telemetry evidence is incomplete.' }
} finally { $token = $null }
