$ErrorActionPreference = 'Stop'
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Test-Lab.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Failover operator does not parse.' }
$dispatch = @($ast.FindAll({
    param($node)
    $node -is [Management.Automation.Language.PipelineAst] -and
        $node.Extent.Text.StartsWith('& ssh @sshArgs ') -and $node.Extent.Text.Contains('nohup')
}, $true))
if ($dispatch.Count -ne 1) { throw 'Expected one production failover dispatch.' }
$fixture = @{command = $null}
function ssh {
    param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
    $fixture.command = $Arguments[-1]
    $global:LASTEXITCODE = 0
}
$Duration = '12m'
$sshArgs = @()
. ([scriptblock]::Create($dispatch[0].Extent.Text))
$bash = if ($IsWindows) {
    Join-Path (Split-Path (Split-Path (Get-Command git).Source -Parent) -Parent) 'bin\bash.exe'
} else { (Get-Command bash).Source }
$root = Join-Path ([IO.Path]::GetTempPath()) "csl-dispatch-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $root | Out-Null
$command = $fixture.command.Replace('cd ~/csl', 'cd "$(cygpath -u "$CSL_DISPATCH_ROOT")"').
    Replace('pwsh -NoLogo -NoProfile -File scripts/runner/test.ps1 -Phase failover -Duration 12m', 'sleep 4')
if (-not $IsWindows) { $command = $command.Replace('$(cygpath -u "$CSL_DISPATCH_ROOT")', '$CSL_DISPATCH_ROOT') }
function Invoke-DispatchFixture {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $bash
    $start.ArgumentList.Add('--noprofile'); $start.ArgumentList.Add('--norc')
    $start.ArgumentList.Add('-c'); $start.ArgumentList.Add($command)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['CSL_DISPATCH_ROOT'] = $root
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(1500) -or -not $stdout.Wait(1500) -or -not $stderr.Wait(1500)) {
            throw 'Background workload retained the dispatch process or SSH output channels.'
        }
        return @{exitCode = $process.ExitCode; error = $stderr.Result}
    } finally { $process.Dispose() }
}
try {
    $first = Invoke-DispatchFixture
    if ($first.exitCode -ne 0) { throw "Background dispatch failed: $($first.error)" }
    if (Test-Path (Join-Path $root 'failover.exit')) { throw 'Dispatch waited for workload completion.' }
    $second = Invoke-DispatchFixture
    if ($second.exitCode -ne 1 -or $second.error -notlike '*prior failover workload*') {
        throw 'A second dispatch did not reject the running prior workload.'
    }
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    while (-not (Test-Path (Join-Path $root 'failover.exit'))) {
        if ([DateTimeOffset]::UtcNow -ge $deadline) { throw 'Detached workload did not publish its exit marker.' }
        Start-Sleep -Milliseconds 100
    }
    if ((Get-Content (Join-Path $root 'failover.exit') -Raw).Trim() -ne '0') { throw 'Detached workload failed.' }
    'Actual production shell dispatch releases output before workload completion, records exit status and rejects overlap.'
} finally {
    Start-Sleep -Seconds 4
    Remove-Item -LiteralPath $root -Recurse
}
