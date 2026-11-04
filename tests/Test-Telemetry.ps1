$ErrorActionPreference = 'Stop'
$path = Join-Path $PSScriptRoot '..\scripts\runner\telemetry.ps1'
$fixture = @{rows = @(); report = $null}
function Get-Content([string] $Path, [switch] $Raw) {
    if ($Path -notlike '*runner-config.json') { throw 'Unexpected telemetry fixture read.' }
    @{
        RUNNER_CLIENT_ID = [Guid]::NewGuid().ToString()
        LOG_ANALYTICS_WORKSPACE_ID = [Guid]::NewGuid().ToString()
    } | ConvertTo-Json
}
function az {
    param([Alias('o')][string] $Output, [Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    $global:LASTEXITCODE = 0
    if ($Arguments[0] -eq 'account') { 'fixture-token' }
}
function Invoke-RestMethod([string] $Uri, [string] $Method, [object] $Headers, [string] $Body, [string] $ContentType, [int] $TimeoutSec) {
    $query = ($Body | ConvertFrom-Json).query
    if ($query -notmatch 'union withsource=SourceTable isfuzzy=true' -or
        $query -notmatch 'summarize Records=count\(\) by SourceTable$' -or $query -match 'by Type$') {
        throw 'Telemetry must group by source table rather than the event-severity Type column.'
    }
    @{tables = @(@{rows = $fixture.rows})}
}
function New-Item([string] $Path, [string] $ItemType, [switch] $Force) {}
function Set-Content {
    param([string] $Path, [Parameter(ValueFromPipeline)][string] $Value, [string] $Encoding)
    process { $fixture.report = $Value | ConvertFrom-Json }
}
foreach ($case in @(
    @{rows = @(@('AppRequests', 3), @('ContainerAppSystemLogs', 2), @('ContainerAppConsoleLogs', 7)); rejected = $false}
    @{rows = @(@('AppRequests', 3), @('Normal', 127), @('Warning', 18)); rejected = $true}
    @{rows = @(@('ContainerAppSystemLogs', 2), @('ContainerAppConsoleLogs', 7)); rejected = $true}
)) {
    $fixture.rows = $case.rows
    $fixture.report = $null
    $rejected = $false
    $failure = $null
    try { & $path } catch { $rejected = $true; $failure = $_.Exception.Message }
    if ($rejected -ne $case.rejected -or $null -eq $fixture.report -or
        ($fixture.report.status -eq 'PASS') -eq $case.rejected) {
        throw "Telemetry fixture failed: rejected=$rejected; reportMissing=$($null -eq $fixture.report); error=$failure"
    }
}
'Source-table provenance and explicit rejection of missing application/system telemetry passed.'
