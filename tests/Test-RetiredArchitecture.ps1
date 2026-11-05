$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
foreach ($name in @('Invoke-LabCycle', 'Register-Controller', 'Set-LabLifecycle', 'Destroy-Lab')) {
    if (Test-Path (Join-Path $root "scripts\$name.ps1")) {
        throw "An obsolete lifecycle/controller entrypoint remains: $name."
    }
}
$common = Get-Content (Join-Path $root 'scripts\Lab.Common.ps1') -Raw
$configuration = Get-Content (Join-Path $root 'config\lab.json') -Raw | ConvertFrom-Json -AsHashtable
if ($configuration.ContainsKey('lifecycle') -or
    $configuration.operations.repairExistingResources -ne $true -or
    $configuration.operations.runRequestedTests -ne $true -or
    $common -match 'With explicit operator approval|Obtain approval|No two-zone or Windows fallback is authorized') {
    throw 'An obsolete operational permission barrier remains in active source/configuration.'
}
if ($common -match 'Start-Job|vm-csl-worker|New-LabLifecycleParameters' -or
    (Test-Path (Join-Path $root 'scripts\runbooks\Lifecycle.ps1')) -or
    (Test-Path (Join-Path $root 'infra\worker-bootstrap.bicep'))) {
    throw 'An active worker, background installer or lifecycle runbook remains.'
}
'Obsolete lifecycle/controller entrypoints are removed; native tests retain their technical readiness guards.'
