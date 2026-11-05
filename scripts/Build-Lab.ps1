[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)]
    [ValidateSet('Plan', 'Prerequisites', 'Infrastructure', 'Runner', 'Application', 'NativeScenarios')]
    [string] $Step,
    [ValidateRange(1, 65535)][int] $TunnelPort = 50222
)
if (-not $env:CSL_ENVIRONMENT_FILE) { throw 'Select the approved private environment explicitly.' }
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
$m = Read-LabManifest $ManifestPath
if (-not $m.ContainsKey('architecture') -or $m.architecture -ne 'linux-app-service') {
    throw 'A fresh Linux App Service ownership manifest is required; historical environments cannot be adopted.'
}
Assert-LabPolicyExemptions $m
Assert-LabBuildValidation $Step (Get-Content (Join-Path $script:LabRoot '.azure\deployment-plan.md') -Raw)
$root = Split-Path $ManifestPath -Parent
$lock = [IO.File]::Open("$ManifestPath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
$started = [DateTimeOffset]::UtcNow
try {
    if ($Step -eq 'Plan') {
        $config = Get-Content (Join-Path $script:LabRoot 'config\lab.json') -Raw | ConvertFrom-Json
        $m.outputs['csl-linux-plan'] = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-linux-plan' `
            (Join-Path $script:LabRoot 'infra\modules\app-service-plan.bicep') @{
                location = $script:LabLocation; deploymentInstanceId = $m.deploymentInstanceId
                planSku = $config.workload.appServiceSku
            }
    }
    $target = if ($Step -in @('Application', 'NativeScenarios')) { Get-LabApplicationTarget $m } else { @{ platform = 'linux' } }
    $planId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])/providers/Microsoft.Web/serverfarms/asp-csl-$($target.platform)-baseline"
    $plan = Invoke-LabAz @('rest', '--method', 'get', '--url',
        "https://management.azure.com${planId}?api-version=2025-03-01", '-o', 'json') | ConvertFrom-Json -AsHashtable
    Write-LabJson (Join-Path $root "$Step-actual-plan.json") $plan
    if ($planId -notin $m.resourceIds -or $plan.tags.deploymentInstanceId -ne $m.deploymentInstanceId) {
        throw "Missing or foreign owned $($target.platform) plan."
    }
    Assert-LabAppServicePlan $plan $target.platform
    if ($Step -eq 'Plan') { $m.status = 'PLAN_THREE_ZONE_CAPABLE' }
    elseif ($Step -eq 'Prerequisites') {
        foreach ($scope in @(@{index=1;module='workload'}, @{index=2;module='operations'})) {
            $template = Join-Path $root "$($scope.module)-identities.template.json"
            Export-LabIdentityTemplate (Join-Path $script:LabRoot "infra\modules\$($scope.module).bicep") $template
            $m.outputs["csl-$($scope.module)-identities"] = Invoke-LabDeployment $m $ManifestPath `
                $script:LabGroups[$scope.index] "csl-$($scope.module)-identities" $template @{
                    location=$script:LabLocation; deploymentInstanceId=$m.deploymentInstanceId
                }
        }
        Get-LabPrerequisitePrincipalIds $m | Out-Null
        $m.status = 'PREREQUISITES_CREATED'
    } elseif ($Step -eq 'Infrastructure') {
        Assert-LabRegionalCapabilities
        $key = Join-Path $root 'runner-key'
        if (-not (Test-Path -LiteralPath $key)) {
            & ssh-keygen -q -t rsa -b 4096 -f $key -N ''
            if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' }
        }
        $m.sshKeyPath = $key
        $revision = (& git -C $script:LabRoot rev-parse HEAD).Trim()
        if ($LASTEXITCODE -ne 0) { throw 'Source revision lookup failed.' }
        $m.sourceRevision = $revision
        $m.outputs['csl-infrastructure'] = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[0] 'csl-infrastructure' `
            (Join-Path $script:LabRoot 'infra\main.bicep') @{
                location=$script:LabLocation; chaosWorkspaceLocation=$script:LabChaosLocation
                operationsLocation=$script:LabOperationsLocation; labSubscriptionId=$script:LabSubscription
                networkResourceGroupName=$script:LabGroups[0]; workloadResourceGroupName=$script:LabGroups[1]
                operationsResourceGroupName=$script:LabGroups[2]; deploymentInstanceId=$m.deploymentInstanceId
                prerequisitePrincipalIds=(Get-LabPrerequisitePrincipalIds $m)
                runnerSshPublicKey=(Get-Content "$key.pub" -Raw).Trim()
                postgresqlAdministratorPassword=([Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))+'a!7')
                sourceRevision=$revision
            }
        $m.status = 'INFRASTRUCTURE_CREATED'
    } elseif ($Step -eq 'Runner') {
        Initialize-LabMachines -ManifestPath $ManifestPath -ManifestLock $lock
        $m = Read-LabManifest $ManifestPath
        $m.status = 'RUNNER_SOFTWARE_INSTALLED'
    } elseif ($Step -eq 'Application') {
        $w = $target
        $o = $m.outputs['csl-infrastructure'].operations.value
        Wait-LabSsh $m $root $TunnelPort
        $options = @(Get-LabSshOptions $m $root)
        $sshArgs = $options + @('-p', [string]$TunnelPort, 'csloperator@127.0.0.1')
        $publish = Join-Path $root "publish-$([Guid]::NewGuid().ToString('N'))"
        & dotnet publish (Join-Path $script:LabRoot 'src\Demo.Api\Demo.Api.csproj') -c Release --no-restore -o $publish
        if ($LASTEXITCODE -ne 0) { throw 'Versioned application publication build failed.' }
        $package = "$publish.zip"
        [IO.Compression.ZipFile]::CreateFromDirectory($publish, $package)
        $m.applicationPackageSha256 = (Get-FileHash $package -Algorithm SHA256).Hash.ToLowerInvariant()
        $config = @{
            SUBSCRIPTION_ID=$script:LabSubscription; DEPLOYMENT_ID=$m.deploymentInstanceId
            RUNNER_CLIENT_ID=$o.runnerClientId; MIGRATION_CLIENT_ID=$w.migrationClientId
            RUNTIME_PRINCIPAL_ID=$w.runtimePrincipalId; POSTGRES_HOST=$w.postgresHost
            VAULT_NAME=$w.vaultName; API_FQDN=$w.applicationFqdn; SCM_FQDN=$w.scmFqdn
            APP_NAME=$w.applicationName; APP_RESOURCE_GROUP=$script:LabGroups[1]
            LOG_ANALYTICS_WORKSPACE_ID=$w.logAnalyticsCustomerId
            PACKAGE_SHA256=$m.applicationPackageSha256
            SOURCE_REVISION=$m.sourceRevision
        }
        $configPath = Join-Path $root 'runner-config.json'
        Write-LabJson $configPath $config
        $bundle = Join-Path $root "runner-source-$([Guid]::NewGuid().ToString('N')).zip"
        $entries = @(foreach ($folder in @('src\Demo.Api\Migrations', 'tests\load', 'scripts\runner')) {
            Get-ChildItem (Join-Path $script:LabRoot $folder) -Recurse -File
        })
        $zip = [IO.Compression.ZipFile]::Open($bundle, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in $entries) {
                $relative = [IO.Path]::GetRelativePath($script:LabRoot, $file.FullName).Replace('\', '/')
                if ($file.Extension -eq '.sh') {
                    $writer = [IO.StreamWriter]::new($zip.CreateEntry($relative).Open(), [Text.UTF8Encoding]::new($false))
                    try { $writer.Write([IO.File]::ReadAllText($file.FullName).Replace("`r`n", "`n")) }
                    finally { $writer.Dispose() }
                } else {
                    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $relative) | Out-Null
                }
            }
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $configPath, 'runner-config.json') | Out-Null
            [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $package, 'application.zip') | Out-Null
        } finally { $zip.Dispose() }
        $m.applicationSourceBundleSha256 = (Get-FileHash $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
        $m.applicationPackagePath = $package
        $m.applicationPublicationState = 'PACKAGE_PREPARED'
        Write-LabJson $ManifestPath $m
        & scp @options -P $TunnelPort $bundle 'csloperator@127.0.0.1:source.zip'
        if ($LASTEXITCODE -ne 0) { throw 'Private source/package transfer failed.' }
        Write-Information 'Private bootstrap/publication output is buffered in ~/csl/bootstrap.log; the guest stage has a 20-minute deadline.' -InformationAction Continue
        & ssh @sshArgs 'mkdir -p ~/csl && unzip -o source.zip -d ~/csl >/dev/null && cd ~/csl && timeout 1200 bash scripts/runner/bootstrap.sh > bootstrap.log 2>&1'
        if ($LASTEXITCODE -ne 0) { throw 'Private migration/SCM package publication failed. Inspect the buffered guest log; resources were preserved.' }
        & ssh @sshArgs 'cd ~/csl && timeout 600 pwsh -NoLogo -NoProfile -File scripts/runner/verify.ps1 > verification.log 2>&1'
        if ($LASTEXITCODE -ne 0) { throw 'Private API authentication/DNS/durability verification failed.' }
        & ssh @sshArgs 'cd ~/csl && timeout 330 pwsh -NoLogo -NoProfile -File scripts/runner/qualify-app.ps1 -OutputPath results/publication-participation.json'
        if ($LASTEXITCODE -ne 0) { throw 'Private all-instance participation probes failed after publication.' }
        $participationPath = Join-Path $root 'publication-participation.json'
        & scp @options -P $TunnelPort 'csloperator@127.0.0.1:csl/results/publication-participation.json' $participationPath
        if ($LASTEXITCODE -ne 0) { throw 'Private all-instance participation evidence retrieval failed.' }
        $participation = Get-Content $participationPath -Raw | ConvertFrom-Json
        $instances = Invoke-LabAz @('rest', '--method', 'get', '--url',
            "https://management.azure.com$($w.applicationId)/instances?api-version=2025-03-01", '-o', 'json') |
            ConvertFrom-Json -AsHashtable
        Assert-LabAppServicePlacement $plan $instances.value $participation.observations $w.platform
        $configuration=(Invoke-LabArm GET "https://management.azure.com$($w.applicationId)/config/web?api-version=2025-03-01").body
        Write-LabJson (Join-Path $root 'publication-app-configuration.json') $configuration
        Assert-LabAppServiceConfiguration $configuration.properties $w.platform
        $m.status = 'PRIVATE_APPLICATION_PUBLISHED'
        $m.applicationPublicationState = 'PRIVATE_PUBLICATION_VERIFIED'
    } elseif ($Step -eq 'NativeScenarios') {
        $w = $target
        if (-not $m.ContainsKey($w.nativeSelectionKey)) { throw 'BLOCKED: retain actual private participation and subscription zone-mapping proof before creating native definitions.' }
        $selection = $m[$w.nativeSelectionKey]
        $proof = Get-Content -LiteralPath $selection.participationProofPath -Raw | ConvertFrom-Json
        $instances = Invoke-LabAz @('rest', '--method', 'get', '--url',
            "https://management.azure.com$($w.applicationId)/instances?api-version=2025-03-01", '-o', 'json') |
            ConvertFrom-Json -AsHashtable
        Assert-LabAppServicePlacement $plan $instances.value $proof.observations $w.platform
        $locations = Invoke-LabAz @('account', 'list-locations', '--query',
            "[?name=='$script:LabLocation'].{name:name,availabilityZoneMappings:availabilityZoneMappings}", '-o', 'json') |
            ConvertFrom-Json -AsHashtable -NoEnumerate
        if ($locations.Count -ne 1 -or $locations[0].name -ne $script:LabLocation) {
            throw 'BLOCKED: exact subscription/region availability-zone mapping is unavailable.'
        }
        $matched = @($instances.value | Where-Object name -eq $selection.instanceId)
        $zone = @($locations[0].availabilityZoneMappings | Where-Object logicalZone -eq $selection.logicalZone)
        if ($selection.applicationId -ine $w.applicationId -or $matched.Count -ne 1 -or $zone.Count -ne 1 -or
            $zone[0].physicalZone -cne $selection.physicalZone -or
            $selection.physicalZone -notin @($instances.value.properties.physicalZone)) {
            throw 'BLOCKED: native instance or logical-to-physical zone selection no longer matches actual owned placement.'
        }
        $m.outputs[$w.nativeScenariosOutput] = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] `
            $w.nativeScenariosOutput (Join-Path $script:LabRoot 'infra\native-process-scenarios.bicep') @{
                workspaceName=$w.chaosWorkspaceName; applicationResourceId=$w.applicationId
                instanceId=$selection.instanceId; logicalZone=$selection.logicalZone; platform=$w.platform
            }
        $m.status = 'NATIVE_DEFINITIONS_CREATED'
    }
    Write-LabJson $ManifestPath $m
    Write-Information "Build stage $Step completed. Actual instance/health/traffic readiness and native tests require separate qualification." -InformationAction Continue
} finally {
    Write-LabJson (Join-Path $root "$Step-timing.json") @{
        startedAtUtc=$started.ToString('O');finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')
        elapsedSeconds=([DateTimeOffset]::UtcNow-$started).TotalSeconds
    }
    $lock.Dispose()
}
