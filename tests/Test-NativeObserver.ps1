$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path ([IO.Path]::GetTempPath()) "csl-observer-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path (Join-Path $fixture 'scripts\runner') -Force | Out-Null
Copy-Item (Join-Path $root 'scripts\runner\observe.ps1') (Join-Path $fixture 'scripts\runner')
@{API_FQDN='fixture.invalid';RUNNER_CLIENT_ID='fixture-runner';VAULT_NAME='fixture-vault'} |
    ConvertTo-Json | Set-Content (Join-Path $fixture 'runner-config.json')
$observerFixture=@{contentType='application/json';content='{"dependencies":{"postgresql":"unavailable"}}'}
function az {
    $global:LASTEXITCODE=0
    if($args[0] -eq 'keyvault') { 'fixture-only-not-a-credential' }
}
function Invoke-WebRequest {
    param($Uri,$Headers,[switch]$SkipHttpErrorCheck,$TimeoutSec)
    [pscustomobject]@{StatusCode=503;Content=$observerFixture.content;Headers=@{
        'Content-Type'=@($observerFixture.contentType)
        'X-Lab-Instance-Id'=@('fixture-instance');'X-Lab-Process-Id'=@('101')
        'X-Lab-Process-Start-Utc'=@('2026-01-01T00:00:00Z')
    }}
}
function Start-Sleep { param($Seconds) throw 'fixture-observer-complete' }
try {
    foreach($kind in @('json','html')) {
        $id=[Guid]::NewGuid().ToString('N')
        if($kind -eq 'html') {
            $observerFixture.contentType='text/html'
            $observerFixture.content='<html>Service unavailable</html>'
        }
        $stopped=$false
        try { & (Join-Path $fixture 'scripts\runner\observe.ps1') -RunId $id -Seconds 60 }
        catch { $stopped=$_.Exception.Message -eq 'fixture-observer-complete' }
        if(-not $stopped) { throw 'Native observer did not survive the two expected fault responses.' }
        $directory=Join-Path $fixture "results\observer-$id"
        $events=@(Get-Content (Join-Path $directory 'observations.ndjson') | ForEach-Object { $_ | ConvertFrom-Json })
        $dependency=@($events | Where-Object kind -eq dependencies)[0]
        if($events.Count -ne 2 -or $dependency.statusCode -ne 503) { throw 'Expected fault observations were omitted.' }
        if($kind -eq 'json' -and ($dependency.dependencyStatus -ne 'unavailable' -or $dependency.error)) {
            throw 'Authenticated PostgreSQL disruption was not preserved.'
        }
        if($kind -eq 'html' -and ($dependency.dependencyStatus -or $dependency.error -notlike '*non-JSON*unverified*')) {
            throw 'An HTML frontend failure was mistaken for verified PostgreSQL disruption.'
        }
    }
    'The actual native observer preserves expected frontend failures and distinguishes verified PostgreSQL disruption.'
} finally { Remove-Item -LiteralPath $fixture -Recurse }
