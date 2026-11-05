$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $PSScriptRoot '..\scripts\Test-Lab.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count) { throw 'Private command orchestration does not parse.' }
$definition=$ast.Find({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-PrivateCommand'
},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$executable=(Microsoft.PowerShell.Core\Get-Command pwsh -ErrorAction Stop).Source
function Get-Command {
    param($Name,$ErrorAction)
    if($Name -ne 'ssh') { throw 'Unexpected fixture executable.' }
    [pscustomobject]@{Source=$executable}
}
$sshArgs=@('-NoLogo','-NoProfile','-Command')
$job=$null
try {
    $job=Start-PrivateCommand observer fixture "Write-Output 'OBSERVER_READY:fixture'; Start-Sleep -Seconds 1; Write-Output 'completed'" 'OBSERVER_READY:fixture'
    $job.process.StandardInput.Close()
    if(-not $job.process.WaitForExit(10000)) { throw 'Fixture observer did not finish.' }
    if($job.process.ExitCode -ne 0 -or $job.stdout.GetAwaiter().GetResult().Trim() -ne 'completed') {
        throw 'Readiness consumption lost subsequent observer output.'
    }
    $job.process.Dispose()
    $job=$null
    $rejected=$false
    try { Start-PrivateCommand observer fixture "Write-Output 'OBSERVER_READY:other'" 'OBSERVER_READY:fixture' | Out-Null }
    catch { $rejected=$_.Exception.Message -like 'Private observer readiness failed*' }
    if(-not $rejected) { throw 'Wrong RunId observer readiness was accepted.' }
    'Private observer startup requires the exact readiness marker and preserves subsequent output.'
} finally {
    if($null -ne $job) {
        if(-not $job.process.HasExited) { Stop-Process -Id $job.process.Id -Force }
        $job.process.Dispose()
    }
}
