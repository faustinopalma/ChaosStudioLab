$ErrorActionPreference = 'Stop'
$previousEnvironment = $env:CSL_ENVIRONMENT_FILE
$previousAzure = $env:AZURE_CONFIG_DIR
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-region-$([Guid]::NewGuid().ToString('N')).json"
$config = @{
    subscriptionId=[Guid]::NewGuid().ToString();tenantId=[Guid]::NewGuid().ToString()
    expectedAccount='test@example.invalid';azureConfigDirectory=[IO.Path]::GetTempPath()
    resourceGroups=@{network='rg-test-network';workload='rg-test-workload';operations='rg-test-operations'}
}
try {
    $env:CSL_ENVIRONMENT_FILE = $fixture
    foreach ($region in @('italynorth', 'swedencentral', 'unapproved-region')) {
        $config.deploymentRegion = $region
        $config | ConvertTo-Json | Set-Content -LiteralPath $fixture
        $rejected = $false
        try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
            $rejected = $true
            if ($_.Exception.Message -notlike '*Only italynorth*') { throw }
        }
        if ($rejected -ne ($region -eq 'unapproved-region')) { throw "Regional allowlist mismatch: $region" }
    }
    $env:CSL_ENVIRONMENT_FILE = ''
    $rejected = $false
    try { . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1') } catch {
        $rejected = $_.Exception.Message -like '*Explicitly select the approved private environment*'
    }
    if (-not $rejected) { throw 'Implicit historical profile selection remains possible.' }
    $lab = Get-Content (Join-Path $PSScriptRoot '..\config\lab.json') -Raw | ConvertFrom-Json
    if ($lab.projectDefaultRegion -ne 'italynorth' -or $lab.deploymentRegion -ne 'swedencentral') {
        throw 'Preferred region or current evidenced fallback drifted.'
    }
    'Only Italy North and Sweden Central are accepted; explicit private-profile selection is mandatory.'
} finally {
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironment
    $env:AZURE_CONFIG_DIR = $previousAzure
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture }
}
