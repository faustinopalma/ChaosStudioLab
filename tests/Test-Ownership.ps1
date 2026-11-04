$ErrorActionPreference = 'Stop'
$previousEnvironmentFile = $env:CSL_ENVIRONMENT_FILE
$previousAzureConfig = $env:AZURE_CONFIG_DIR
$fixturePath = Join-Path ([IO.Path]::GetTempPath()) "csl-test-environment-$([Guid]::NewGuid().ToString('N')).json"
@{
    subscriptionId = [Guid]::NewGuid().ToString(); tenantId = [Guid]::NewGuid().ToString()
    expectedAccount = 'test-operator@example.invalid'; azureConfigDirectory = [IO.Path]::GetTempPath()
    deploymentRegion = 'swedencentral'
    resourceGroups = @{network = 'rg-test-network'; workload = 'rg-test-workload'; operations = 'rg-test-operations'}
} | ConvertTo-Json | Set-Content -LiteralPath $fixturePath
$env:CSL_ENVIRONMENT_FILE = $fixturePath
. (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1')
$temp = Join-Path ([System.IO.Path]::GetTempPath()) "csl-ownership-$([Guid]::NewGuid().ToString('N')).json"
$m = @{
    schemaVersion = 1; subscriptionId = $script:LabSubscription; tenantId = $script:LabTenant
    labId = 'lab-dev01'; deploymentInstanceId = [Guid]::NewGuid().ToString('N')
    groups = @($script:LabGroups | ForEach-Object {
        @{ name = $_; id = "/subscriptions/$script:LabSubscription/resourceGroups/$_" }
    })
    resourceIds = @("/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[0])/providers/Microsoft.Network/virtualNetworks/vnet-csl-hub")
}
function Expect-Rejected([scriptblock] $Action) {
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    if (-not $rejected) { throw 'Ownership safety check accepted invalid input.' }
}
try {
    foreach ($values in @(@(), @('single'), @('one', 'two'))) {
        Write-LabJson $temp $values
        $roundtrip = Get-Content -LiteralPath $temp -Raw | ConvertFrom-Json -NoEnumerate
        if ($roundtrip -isnot [array] -or $roundtrip.Count -ne $values.Count) {
            throw 'JSON evidence did not preserve the root array shape.'
        }
    }
    Write-LabJson $temp $m
    $valid = Read-LabManifest $temp
    Assert-LabDestroyInventory $valid $valid.resourceIds
    Expect-Rejected { Assert-LabResourceId '/subscriptions/foreign/resourceGroups/foreign/providers/Microsoft.Compute/virtualMachines/vm' }
    Expect-Rejected { Assert-LabDestroyInventory $valid @("$($valid.resourceIds[0])-foreign") }
    $m.labId = 'foreign'
    Write-LabJson $temp $m
    Expect-Rejected { Read-LabManifest $temp }
    $m.labId = 'lab-dev01'
    $m.groups[0].id += '-foreign'
    Write-LabJson $temp $m
    Expect-Rejected { Read-LabManifest $temp }
    $m.groups[0].id = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[0])"
    $m.outputs = @{}
    $script:previewChanges = @(@{ resourceId = $m.resourceIds[0]; changeType = 'Create' })
    $script:deployCalls = 0
    function Invoke-LabAz([string[]] $Arguments) {
        if ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'exists') { return 'false' }
        if ($Arguments[2] -eq 'what-if') {
            if ('--no-pretty-print' -notin $Arguments) { throw 'Missing machine-readable preview flag.' }
            return (@{status='Succeeded';error=$null;changes=$script:previewChanges} | ConvertTo-Json -Depth 10)
        }
        if ($Arguments[2] -eq 'create') {
            $script:deployCalls++
            return '{"properties":{"outputs":{}}}'
        }
        throw 'Unexpected mock CLI operation.'
    }
    $name = "csl-safety-$([Guid]::NewGuid().ToString('N'))"
    Invoke-LabDeployment $m $temp $script:LabGroups[0] $name 'unused.bicep' @{} | Out-Null
    if ($script:deployCalls -ne 1) { throw 'A successful preview with a null error did not deploy.' }
    $script:previewChanges[0].changeType = 'Delete'
    Expect-Rejected { Invoke-LabDeployment $m $temp $script:LabGroups[0] $name 'unused.bicep' @{} }
    $script:previewChanges[0].changeType = 'Modify'
    Expect-Rejected { Invoke-LabDeployment $m $temp $script:LabGroups[0] $name 'unused.bicep' @{} }
    $script:previewChanges[0].changeType = 'Unsupported'
    Expect-Rejected { Invoke-LabDeployment $m $temp $script:LabGroups[0] $name 'unused.bicep' @{} }
    $publicIpId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[0])/providers/Microsoft.Network/publicIPAddresses/pip-csl-hub-firewall"
    $script:previewChanges = @(@{
        resourceId = $publicIpId; changeType = 'Create'
        after = @{
            sku = @{ name = 'Standard' }
            properties = @{
                publicIPAllocationMethod = 'Static'; publicIPAddressVersion = 'IPv4'
                ipTags = @(@{ ipTagType = 'FirstPartyUsage'; tag = '/Unprivileged' })
            }
        }
    })
    Expect-Rejected { Invoke-LabDeployment $m $temp $script:LabGroups[0] $name 'unused.bicep' @{} }
    if ($script:deployCalls -ne 1) { throw 'A forbidden preview reached deployment.' }
    $publicIp = $script:previewChanges[0]
    $publicIp.after.properties.Remove('ipTags')
    Assert-LabPublicIpChanges @($publicIp)
    foreach ($tags in @($null, @())) {
        $publicIp.after.properties.ipTags = $tags
        Assert-LabPublicIpChanges @($publicIp)
    }
    $publicIp.after.properties.Remove('ipTags')
    $validPayload = $publicIp.after
    $publicIp.after = $null
    Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
    $publicIp.after = $validPayload
    foreach ($property in @('publicIPPrefix', 'customIPPrefix', 'ipAddress')) {
        $publicIp.after.properties[$property] = 'forbidden'
        Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
        $publicIp.after.properties.Remove($property)
    }
    foreach ($prefixType in @('publicIPPrefixes', 'customIPPrefixes')) {
        $publicIp.resourceId = $publicIpId.Replace('publicIPAddresses', $prefixType)
        Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
    }
    $publicIp.resourceId = $publicIpId
    $publicIp.after.sku.name = 'Basic'
    Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
    $publicIp.after.sku.name = 'Standard'
    $publicIp.after.properties.publicIPAllocationMethod = 'Dynamic'
    Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
    $publicIp.after.properties.publicIPAllocationMethod = 'Static'
    $publicIp.after.properties.publicIPAddressVersion = 'IPv6'
    Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
    $publicIp.after.properties.publicIPAddressVersion = 'IPv4'
    $publicIp.changeType = 'Modify'
    $publicIp.before = @{ properties = @{ ipAddress = '192.0.2.1' } }
    $publicIp.after.properties.ipAddress = '192.0.2.1'
    Assert-LabPublicIpChanges @($publicIp)
    $publicIp.after.properties.ipAddress = '192.0.2.2'
    Expect-Rejected { Assert-LabPublicIpChanges @($publicIp) }
    $script:exemptionId = "$($m.groups[0].id)/providers/Microsoft.Authorization/policyExemptions/csl-test"
    function Invoke-LabAz([string[]] $Arguments) {
        if ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'exists') {
            return $(if ($Arguments[3] -eq $script:LabGroups[0]) { 'true' } else { 'false' })
        }
        if ($Arguments[0] -eq 'group' -and $Arguments[1] -eq 'show') {
            return (@{tags = @{deploymentInstanceId = $m.deploymentInstanceId; labId = $m.labId}} | ConvertTo-Json)
        }
        if ($Arguments[0] -eq 'resource' -and $Arguments[1] -eq 'list') { return '[]' }
        if ($Arguments[0] -eq 'policy' -and $Arguments[1] -eq 'exemption' -and $Arguments[2] -eq 'list') {
            if ($Arguments[4] -ne $m.groups[0].id -or $Arguments[6] -ne 'false') {
                throw 'Exemption inventory scope drifted.'
            }
            return (@(@{id = $script:exemptionId}) | ConvertTo-Json -AsArray)
        }
        throw 'Unexpected exemption inventory operation.'
    }
    $m.Remove('deploymentRoots')
    $exemptionInventory = @(Get-LabInventory $m)
    if ($exemptionInventory.Count -ne 1 -or $exemptionInventory[0] -ne $script:exemptionId) {
        throw 'Policy exemption was omitted from the cleanup inventory.'
    }
    Expect-Rejected { Assert-LabDestroyInventory $m $exemptionInventory }
    $m.resourceIds = $exemptionInventory
    Assert-LabDestroyInventory $m $exemptionInventory
    $script:exemptionId = '/subscriptions/foreign/resourceGroups/foreign/providers/Microsoft.Authorization/policyExemptions/foreign'
    Expect-Rejected { Get-LabInventory $m }
    Remove-Item -LiteralPath (Join-Path (Split-Path $temp -Parent) "$name.what-if.json")
    Remove-Item -LiteralPath (Join-Path (Split-Path $temp -Parent) "$name.deployment.json")
    Write-Output 'Ownership, exact-scope previews, and BYOIP-free public-IP contract tests passed.'
} finally {
    Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixturePath
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironmentFile
    $env:AZURE_CONFIG_DIR = $previousAzureConfig
}
