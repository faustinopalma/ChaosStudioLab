$ErrorActionPreference = 'Stop'
$previousEnvironment = $env:CSL_ENVIRONMENT_FILE
$previousAzureConfig = $env:AZURE_CONFIG_DIR
$fixture = Join-Path ([IO.Path]::GetTempPath()) "csl-identity-environment-$([Guid]::NewGuid().ToString('N')).json"
$output = Join-Path ([IO.Path]::GetTempPath()) "csl-identity-template-$([Guid]::NewGuid().ToString('N')).json"
@{
    subscriptionId = [Guid]::NewGuid().ToString(); tenantId = [Guid]::NewGuid().ToString()
    expectedAccount = 'test-operator@example.invalid'; azureConfigDirectory = [IO.Path]::GetTempPath()
    deploymentRegion = 'swedencentral'
    resourceGroups = @{network = 'rg-test-network'; workload = 'rg-test-workload'; operations = 'rg-test-operations'}
} | ConvertTo-Json | Set-Content -LiteralPath $fixture
try {
    $env:CSL_ENVIRONMENT_FILE = $fixture
    . (Join-Path $PSScriptRoot '..\scripts\Lab.Common.ps1')
    $boundedPlan = "**Status:** Validated`n**Validated build steps:** Prerequisites"
    Assert-LabBuildValidation 'Prerequisites' $boundedPlan
    foreach ($case in @(
        @{step = 'Infrastructure'; plan = $boundedPlan}
        @{step = 'Runner'; plan = $boundedPlan}
        @{step = 'Prerequisites'; plan = '**Status:** Ready for Validation'}
        @{step = 'Infrastructure'; plan = '**Status:** Validated'}
        @{step = 'Plan'; plan = "**Status:** Blocked`n**Validated build steps:** Scope"}
    )) {
        $rejected = $false
        try { Assert-LabBuildValidation $case.step $case.plan } catch { $rejected = $true }
        if (-not $rejected) { throw 'A build step exceeded the validated phase.' }
    }
    foreach ($module in @('workload', 'operations')) {
        $path = Join-Path $script:LabRoot "infra\modules\$module.bicep"
        $source = Invoke-LabAz @('bicep', 'build', '--file', $path, '--stdout') | ConvertFrom-Json -AsHashtable
        Export-LabIdentityTemplate $path $output
        $actual = Get-Content -LiteralPath $output -Raw | ConvertFrom-Json -AsHashtable
        $expected = @($source.resources | Where-Object type -eq 'Microsoft.ManagedIdentity/userAssignedIdentities')
        $count = if ($module -eq 'workload') { 3 } else { 1 }
        if ($actual.resources.Count -ne $count -or
            (ConvertTo-Json -InputObject $actual.resources -Depth 50 -Compress) -ne
            (ConvertTo-Json -InputObject $expected -Depth 50 -Compress)) {
            throw 'Identity prerequisite resource payloads differ from the main source.'
        }
        if ($actual.parameters.Count -ne 2 -or $actual.variables.Count -ne 1 -or
            $actual.variables.labTags.deploymentInstanceId -ne "[parameters('deploymentInstanceId')]" -or
            $actual.resources[0].location -ne "[parameters('location')]") {
            throw 'Identity prerequisite scope, location or ownership contract drifted.'
        }
    }
    $script:invalidIdentitySource = $source
    $script:invalidIdentitySource.resources = @(@{
        type = 'Microsoft.ManagedIdentity/userAssignedIdentities'; dependsOn = @('unexpected')
    })
    $instance = [Guid]::NewGuid().ToString('N')
    $script:identityRecords = @(
        foreach ($spec in @(
            @{index = 1; name = 'id-csl-migrations'}, @{index = 2; name = 'id-csl-runner'}
            @{index = 1; name = 'id-csl-chaos'}, @{index = 1; name = 'id-csl-runtime'}
        )) {
            @{
                id = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[$spec.index])/providers/Microsoft.ManagedIdentity/userAssignedIdentities/$($spec.name)"
                principalId = [Guid]::NewGuid().ToString(); tags = @{deploymentInstanceId = $instance}
            }
        }
    )
    $identityManifest = @{deploymentInstanceId = $instance; resourceIds = @($script:identityRecords.id)}
    function Invoke-LabAz([string[]] $Arguments) {
        if ($Arguments[0] -eq 'identity') {
            return (ConvertTo-Json -InputObject @($script:identityRecords |
                Where-Object { $_.id -like "*/resourceGroups/$($Arguments[3])/providers/*" }) -Depth 20)
        }
        ConvertTo-Json -InputObject $script:invalidIdentitySource -Depth 50
    }
    $principals = Get-LabPrerequisitePrincipalIds $identityManifest
    if ($principals.Count -ne 4 -or $principals.migration -ne $script:identityRecords[0].principalId) {
        throw 'Live prerequisite principals were not resolved from exact owned identities.'
    }
    foreach ($index in 0..3) {
        foreach ($case in @('invalid-principal', 'foreign-owner', 'unrecorded-identity')) {
            $original = $script:identityRecords[$index].principalId
            if ($case -eq 'invalid-principal') { $script:identityRecords[$index].principalId = 'invalid' }
            if ($case -eq 'foreign-owner') { $script:identityRecords[$index].tags.deploymentInstanceId = 'foreign' }
            if ($case -eq 'unrecorded-identity') {
                $identityManifest.resourceIds = @($script:identityRecords.id | Where-Object { $_ -ne $script:identityRecords[$index].id })
            }
            $rejected = $false
            try { Get-LabPrerequisitePrincipalIds $identityManifest | Out-Null } catch { $rejected = $true }
            if (-not $rejected) { throw "Accepted unsafe prerequisite input for identity $index`: $case" }
            $script:identityRecords[$index].principalId = $original
            $script:identityRecords[$index].tags.deploymentInstanceId = $instance
            $identityManifest.resourceIds = @($script:identityRecords.id)
        }
    }
    $rejected = $false
    try { Export-LabIdentityTemplate 'unused.bicep' $output } catch { $rejected = $true }
    if (-not $rejected) { throw 'A dependent identity was accepted as an independent prerequisite.' }
    $startup = @{writes = 0}
    function az {
        param([Parameter(ValueFromRemainingArguments)][string[]] $Arguments)
        $global:LASTEXITCODE = 0
        if ($Arguments[0] -eq 'account' -and $Arguments[1] -eq 'show') {
            return (ConvertTo-Json @{
                id = $script:LabSubscription; tenantId = $script:LabTenant
                user = @{name = 'test-operator@example.invalid'}
            })
        }
        if ($Arguments[0] -eq 'rest' -and $Arguments -match '/capabilities\?') {
            return '{"value":[{"restricted":"Disabled","zoneRedundantHaSupported":"Enabled"}]}'
        }
        $startup.writes++
        throw 'A bounded-validation startup attempted an unexpected Azure operation.'
    }
    function Get-Content {
        param([string] $Path, [string] $LiteralPath, [switch] $Raw)
        if ($Path -and $Path.EndsWith('.azure\deployment-plan.md')) { return $boundedPlan }
        Microsoft.PowerShell.Management\Get-Content @PSBoundParameters
    }
    $manifestPath = "$output.manifest.json"
    Write-LabJson $manifestPath @{
        schemaVersion = 1; architecture = 'linux-app-service'; subscriptionId = $script:LabSubscription; tenantId = $script:LabTenant
        labId = 'lab-dev01'; deploymentInstanceId = [Guid]::NewGuid().ToString('N'); resourceIds = @()
        groups = @($script:LabGroups | ForEach-Object {
            @{name = $_; id = "/subscriptions/$script:LabSubscription/resourceGroups/$_"}
        })
    }
    $before = Get-Content -LiteralPath $manifestPath -Raw
    foreach ($entrypoint in @('Build-Lab.ps1')) {
        $blocked = $false
        try { & (Join-Path $PSScriptRoot "..\scripts\$entrypoint") -ManifestPath $manifestPath -Step Infrastructure }
        catch { $blocked = $_.Exception.Message -like '*not yet validated for the Infrastructure build step*' }
        if (-not $blocked -or $startup.writes -ne 0 -or
            (Get-Content -LiteralPath $manifestPath -Raw) -cne $before -or
            (Test-Path -LiteralPath "$manifestPath.lock")) {
            throw 'A bounded-validation startup did not preserve the existing lab before cleanup.'
        }
    }
    'Exact-source identity prerequisites preserve payloads, location and ownership; dependencies fail closed.'
} finally {
    Remove-Item Function:\az, Function:\Get-Content -ErrorAction SilentlyContinue
    foreach ($path in @($fixture, $output, "$output.manifest.json")) {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path }
    }
    $env:CSL_ENVIRONMENT_FILE = $previousEnvironment
    $env:AZURE_CONFIG_DIR = $previousAzureConfig
}
