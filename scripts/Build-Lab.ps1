[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)]
    [ValidateSet('Plan', 'Prerequisites', 'Infrastructure', 'Runner', 'Application')]
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
    $planId = "/subscriptions/$script:LabSubscription/resourceGroups/$($script:LabGroups[1])/providers/Microsoft.Web/serverfarms/asp-csl-linux-baseline"
    $plan = Invoke-LabAz @('rest', '--method', 'get', '--url',
        "https://management.azure.com${planId}?api-version=2025-03-01", '-o', 'json') | ConvertFrom-Json -AsHashtable
    Write-LabJson (Join-Path $root "$Step-actual-plan.json") $plan
    if ($planId -notin $m.resourceIds -or $plan.tags.deploymentInstanceId -ne $m.deploymentInstanceId) {
        throw 'Missing or foreign owned Linux plan.'
    }
    Assert-LabAppServicePlan $plan
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
                location=$script:LabLocation; labSubscriptionId=$script:LabSubscription
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
        $w = $m.outputs['csl-infrastructure'].workload.value
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
        & scp @options -P $TunnelPort $bundle 'csloperator@127.0.0.1:source.zip'
        if ($LASTEXITCODE -ne 0) { throw 'Private source/package transfer failed.' }
        Write-Information 'Private bootstrap/publication output is buffered in ~/csl/bootstrap.log; the guest stage has a 20-minute deadline.' -InformationAction Continue
        & ssh @sshArgs 'mkdir -p ~/csl && unzip -o source.zip -d ~/csl >/dev/null && cd ~/csl && timeout 1200 bash scripts/runner/bootstrap.sh > bootstrap.log 2>&1'
        if ($LASTEXITCODE -ne 0) { throw 'Private migration/SCM package publication failed. Inspect the buffered guest log; resources were preserved.' }
        & ssh @sshArgs 'cd ~/csl && timeout 600 pwsh -NoLogo -NoProfile -File scripts/runner/verify.ps1 > verification.log 2>&1'
        if ($LASTEXITCODE -ne 0) { throw 'Private API authentication/DNS/durability verification failed.' }
        $m.status = 'PRIVATE_APPLICATION_PUBLISHED'
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
