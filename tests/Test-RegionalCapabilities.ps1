$ErrorActionPreference = 'Stop'
$previousEnvironment = $env:CSL_ENVIRONMENT_FILE
$previousAzure = $env:AZURE_CONFIG_DIR
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-region-$([Guid]::NewGuid().ToString('N')).json"
@{
    subscriptionId = [Guid]::NewGuid().ToString(); tenantId = [Guid]::NewGuid().ToString()
    expectedAccount = 'test@example.invalid'; azureConfigDirectory = [IO.Path]::GetTempPath()
    deploymentRegion = 'swedencentral'
    resourceGroups = @{network = 'rg-test-network'; workload = 'rg-test-workload'; operations = 'rg-test-operations'}
} | ConvertTo-Json | Set-Content -LiteralPath $fixture
try {
    $env:CSL_ENVIRONMENT_FILE = $fixture
    . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1')
    $script:capabilities = @{value = @(@{
        restricted = 'Disabled'; zoneRedundantHaSupported = 'Enabled'
        supportedServerEditions = @(@{supportedServerSkus = @(@{supportedHaMode = @('ZoneRedundant')})})
    })}
    function Invoke-LabAz([string[]] $Arguments) {
        if ($Arguments[0] -ne 'rest' -or $Arguments[2] -ne 'get' -or
            $Arguments[4] -notlike '*/locations/swedencentral/capabilities?api-version=*') {
            throw 'Unexpected regional preflight operation.'
        }
        ConvertTo-Json -InputObject $script:capabilities -Depth 15
    }
    Assert-LabRegionalCapabilities
    foreach ($case in @('Disabled', $null)) {
        $script:capabilities.value[0].zoneRedundantHaSupported = $case
        $message = $null
        try { Assert-LabRegionalCapabilities } catch { $message = $_.Exception.Message }
        if ($message -notlike '*subscription-level zoneRedundantHaSupported*') {
            throw 'Per-SKU support masked disabled/missing subscription-level HA eligibility.'
        }
    }
    $script:capabilities.value[0].zoneRedundantHaSupported = 'Enabled'
    $script:capabilities.value[0].restricted = 'Enabled'
    $rejected = $false
    try { Assert-LabRegionalCapabilities } catch { $rejected = $true }
    if (-not $rejected) { throw 'Restricted subscription region was accepted.' }
    'Subscription-level regional HA capability tests passed; SKU-only support cannot authorize provisioning.'
} finally {
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironment
    $env:AZURE_CONFIG_DIR = $previousAzure
    Remove-Item -LiteralPath $fixture
}
