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
    foreach ($region in @('italynorth', 'swedencentral', 'spaincentral', 'francecentral', 'switzerlandnorth', 'invalid-region', 'Spain Central', '')) {
        $config.deploymentRegion = $region
        $config | ConvertTo-Json | Set-Content -LiteralPath $fixture
        $rejected = $false
        try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
            $rejected = $true
            if ($_.Exception.Message -notlike '*lowercase location name*' -and
                $_.Exception.Message -notlike '*missing deploymentRegion*') { throw }
        }
        if ($rejected -ne ($region -in @('invalid-region', 'Spain Central', ''))) { throw "Regional name validation mismatch: $region" }
        if (-not $rejected -and $script:LabChaosLocation -ne 'swedencentral') { throw 'Workspace and workload location were conflated.' }
    }
    $config.deploymentRegion = 'spaincentral'
    $config.chaosWorkspaceRegion = 'francecentral'
    $config.operationsRegion = 'switzerlandnorth'
    $config | ConvertTo-Json | Set-Content -LiteralPath $fixture
    . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1')
    if ($script:LabChaosLocation -ne 'francecentral' -or $script:LabOperationsLocation -ne 'switzerlandnorth') {
        throw 'Independent Workspace/operations selection was not preserved.'
    }
    $env:CSL_ENVIRONMENT_FILE = ''
    $rejected = $false
    try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
        $rejected = $_.Exception.Message -like '*Explicitly select the approved private environment*'
    }
    if (-not $rejected) { throw 'Implicit historical profile selection remains possible.' }
    $lab = Get-Content (Join-Path $PSScriptRoot '..\config\lab.json') -Raw | ConvertFrom-Json
    if ($lab.projectDefaultRegion -ne 'spaincentral' -or $lab.deploymentRegion -ne 'spaincentral' -or
        $lab.chaosWorkspaceRegion -ne 'swedencentral') {
        throw 'Preferred region or current evidenced fallback drifted.'
    }
    'Region selection is unrestricted by a project allowlist; valid names, independent placements and explicit profile selection are verified.'
} finally {
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironment
    $env:AZURE_CONFIG_DIR = $previousAzure
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture }
}
