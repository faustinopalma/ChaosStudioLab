$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dll = Join-Path $root 'src\Demo.Api\bin\Release\net9.0\Demo.Api.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build the API in Release before this runtime test.' }
$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = $listener.LocalEndpoint.Port
$listener.Stop()
$start = [Diagnostics.ProcessStartInfo]::new((Get-Command dotnet).Source)
$start.ArgumentList.Add($dll)
$start.WorkingDirectory = Split-Path $dll -Parent
$start.UseShellExecute = $false
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.Environment['ASPNETCORE_URLS'] = "http://127.0.0.1:$port"
$start.Environment['WEBSITE_INSTANCE_ID'] = 'fixture-app-instance'
$start.Environment['LAB_SOURCE_REVISION'] = 'fixture-source'
$process = [Diagnostics.Process]::new()
$process.StartInfo = $start
try {
    if (-not $process.Start()) { throw 'Local API process did not start.' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $response = $null
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if ($process.HasExited) { throw "Local API exited: $($stderr.GetAwaiter().GetResult())" }
        try {
            $response = Invoke-WebRequest "http://127.0.0.1:$port/health/live" -TimeoutSec 1
            break
        } catch [Net.Http.HttpRequestException], [Net.WebException], [Threading.Tasks.TaskCanceledException] {
            if ($attempt -eq 29) { throw }
            Start-Sleep -Milliseconds 200
        }
    }
    if ($null -eq $response) { throw 'Local API did not become live within the bounded probe.' }
    $body = $response.Content | ConvertFrom-Json
    if ($body.status -ne 'live' -or $body.instanceId -ne 'fixture-app-instance' -or
        $body.replicaId -ne $body.instanceId -or $body.revision -ne 'fixture-source' -or
        $body.processId -ne $process.Id -or
        $response.Headers['X-Lab-Instance-Id'][0] -ne $body.instanceId -or
        [int]$response.Headers['X-Lab-Process-Id'][0] -ne $body.processId -or
        [DateTimeOffset]::Parse($response.Headers['X-Lab-Process-Start-Utc'][0]) -ne
            [DateTimeOffset]$body.processStartedAtUtc) {
        throw 'Live application identity/process headers differ from actual runtime identity.'
    }
    $age = [DateTimeOffset]::UtcNow - [DateTimeOffset]$body.processStartedAtUtc
    if ($age.TotalSeconds -lt 0 -or $age.TotalSeconds -gt 40) { throw 'Process-start evidence is not current.' }
    'Local live HTTP responses expose the configured instance/source and actual process ID/start time; legacy replica metadata remains compatible.'
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force; $process.WaitForExit(5000) | Out-Null }
    $process.Dispose()
}
