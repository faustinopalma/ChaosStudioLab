$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($name in @('Invoke-LabCycle', 'Register-Controller', 'Set-LabLifecycle', 'Destroy-Lab', 'Test-Lab')) {
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root "scripts\$name.ps1"), [ref]$tokens, [ref]$errors)
    if ($errors.Count -or $ast.EndBlock.Statements.Count -ne 1 -or
        $ast.EndBlock.Statements[0] -isnot [Management.Automation.Language.ThrowStatementAst]) {
        throw "Retired/unqualified entrypoint $name can execute an operation."
    }
}
$common = Get-Content (Join-Path $root 'scripts\Lab.Common.ps1') -Raw
if ($common -match 'Start-Job|vm-csl-worker|New-LabLifecycleParameters' -or
    (Test-Path (Join-Path $root 'scripts\runbooks\Lifecycle.ps1')) -or
    (Test-Path (Join-Path $root 'infra\worker-bootstrap.bicep'))) {
    throw 'An active worker, background installer or lifecycle runbook remains.'
}
'Retired lifecycle/destruction/cycle entrypoints and unqualified tests fail before any operation; no entrypoint was invoked.'
