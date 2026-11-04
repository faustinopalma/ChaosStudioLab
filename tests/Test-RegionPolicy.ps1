$ErrorActionPreference = 'Stop'
$previousEnvironment = $env:CSL_ENVIRONMENT_FILE
$previousAzure = $env:AZURE_CONFIG_DIR
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-region-$([Guid]::NewGuid().ToString('N')).json"
$config = @{
    subscriptionId=[Guid]::NewGuid().ToString();tenantId=[Guid]::NewGuid().ToString()
    expectedAccount='test@example.invalid';azureConfigDirectory=[IO.Path]::GetTempPath()
    chaosWorkspaceRegion='swedencentral'
    resourceGroups=@{network='rg-test-network';workload='rg-test-workload';operations='rg-test-operations'}
}
try {
    $env:CSL_ENVIRONMENT_FILE = $fixture
    foreach ($region in @('italynorth', 'swedencentral', 'spaincentral', 'unapproved-region', 'westeurope', 'northeurope')) {
        $config.deploymentRegion = $region
        $config | ConvertTo-Json | Set-Content -LiteralPath $fixture
        $rejected = $false
        try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
            $rejected = $true
            if ($_.Exception.Message -notlike '*Only italynorth*') { throw }
        }
        if ($rejected -ne ($region -in @('unapproved-region', 'westeurope', 'northeurope'))) { throw "Regional allowlist mismatch: $region" }
        if (-not $rejected -and $script:LabChaosLocation -ne 'swedencentral') { throw 'Workspace and workload location were conflated.' }
    }
    $config.deploymentRegion = 'spaincentral'
    $config.chaosWorkspaceRegion = 'spaincentral'
    $config | ConvertTo-Json | Set-Content -LiteralPath $fixture
    $rejected = $false
    try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
        $rejected = $_.Exception.Message -like '*qualified swedencentral Chaos Workspace*'
    }
    if (-not $rejected) { throw 'An unqualified Workspace deployment region was accepted.' }
    $env:CSL_ENVIRONMENT_FILE = ''
    $rejected = $false
    try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
        $rejected = $_.Exception.Message -like '*Explicitly select the approved private environment*'
    }
    if (-not $rejected) { throw 'Implicit historical profile selection remains possible.' }
    $lab = Get-Content (Join-Path $PSScriptRoot '..\config\lab.json') -Raw | ConvertFrom-Json
    if ($lab.projectDefaultRegion -ne 'italynorth' -or $lab.deploymentRegion -ne 'spaincentral' -or
        $lab.chaosWorkspaceRegion -ne 'swedencentral') {
        throw 'Preferred region or current evidenced fallback drifted.'
    }
    'Only the three explicitly selected workload candidates are accepted; cross-region Workspace placement and explicit profile selection are enforced.'
} finally {
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironment
    $env:AZURE_CONFIG_DIR = $previousAzure
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture }
}
