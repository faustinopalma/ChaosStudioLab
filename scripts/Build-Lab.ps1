[CmdletBinding()]
param(
    [ValidateSet('Prerequisites', 'Infrastructure', 'Runner', 'Application', 'Controller')]
    [string] $Step = 'Infrastructure',
    [string] $ManifestPath = (Join-Path $PSScriptRoot '..\.local\manifest.json'),
    [int] $TunnelPort = 50222
)
. (Join-Path $PSScriptRoot 'Lab.Common.ps1')
Confirm-LabContext
$startupManifest = if (Test-Path -LiteralPath $ManifestPath) { Read-LabManifest $ManifestPath } else { $null }
Assert-LabPolicyExemptions $startupManifest
if ($Step -in @('Prerequisites', 'Infrastructure')) { Assert-LabRegionalCapabilities }
$plan = Get-Content (Join-Path $script:LabRoot '.azure\deployment-plan.md') -Raw
Assert-LabBuildValidation $Step $plan
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
New-Item -ItemType Directory -Path (Split-Path $ManifestPath -Parent) -Force | Out-Null
$lock = [IO.File]::Open("$ManifestPath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
try {
    if (-not (Test-Path $ManifestPath)) {
        if ($Step -notin @('Prerequisites', 'Infrastructure')) { throw 'Create the owned infrastructure manifest first.' }
        foreach ($g in $script:LabGroups) {
            if ((Invoke-LabAz @('group', 'exists', '-n', $g, '-o', 'tsv')) -ne 'false') {
                throw "Refusing to adopt an existing group: $g"
            }
        }
        $baseline = Invoke-LabAz @('resource', 'list', '--subscription', $script:LabSubscription,
            '--query', '[].{id:id,type:type,group:resourceGroup}', '-o', 'json') | ConvertFrom-Json -AsHashtable
        Write-LabJson (Join-Path (Split-Path $ManifestPath -Parent) 'preexisting-resources.json') $baseline
        $m = @{
            schemaVersion = 1; subscriptionId = $script:LabSubscription; tenantId = $script:LabTenant
            labId = 'lab-dev01'; deploymentInstanceId = [Guid]::NewGuid().ToString('N')
            groups = @($script:LabGroups | ForEach-Object {
                @{ name = $_; id = "/subscriptions/$script:LabSubscription/resourceGroups/$_" }
            })
            resourceIds = @(); outputs = @{}; status = 'BUILDING'
            createdAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        }
        Write-LabJson $ManifestPath $m
    } else { $m = Read-LabManifest $ManifestPath }
    if ($m.status -like 'DESTROYED*') { throw 'Use a new manifest path for a new deployment instance.' }
    $stateRoot = Split-Path $ManifestPath -Parent
    if ($Step -in @('Prerequisites', 'Infrastructure')) {
        foreach ($g in $m.groups) {
            if ((Invoke-LabAz @('group', 'exists', '-n', $g.name, '-o', 'tsv')) -eq 'false') {
                Invoke-LabAz @('group', 'create', '-n', $g.name, '-l', $script:LabLocation, '--tags',
                    'project=ChaosStudioLab', 'labId=lab-dev01', "deploymentInstanceId=$($m.deploymentInstanceId)",
                    'environment=nonproduction', 'owner=lab-operator', '-o', 'none') | Out-Null
            }
        }
        if ($Step -eq 'Prerequisites' -or -not $m.outputs.ContainsKey('csl-workload-identities') -or
            -not $m.outputs.ContainsKey('csl-operations-identities')) {
            foreach ($scope in @(@{ index = 1; module = 'workload' }, @{ index = 2; module = 'operations' })) {
                $identityTemplate = Join-Path $stateRoot "$($scope.module)-identities.template.json"
                try {
                    Export-LabIdentityTemplate (Join-Path $script:LabRoot "infra\modules\$($scope.module).bicep") $identityTemplate
                    Invoke-LabDeployment $m $ManifestPath $script:LabGroups[$scope.index] "csl-$($scope.module)-identities" `
                        $identityTemplate @{ location = $script:LabLocation; deploymentInstanceId = $m.deploymentInstanceId } | Out-Null
                } finally {
                    if (Test-Path -LiteralPath $identityTemplate) { Remove-Item -LiteralPath $identityTemplate }
                }
            }
        } else {
            Get-LabPrerequisitePrincipalIds $m | Out-Null
            Write-Information "[$([DateTimeOffset]::UtcNow.ToString('O'))] Reusing all five live, ownership-verified prerequisite identities." -InformationAction Continue
        }
        if ($Step -eq 'Prerequisites') {
            $m.status = 'PREREQUISITES_CREATED'
            Write-LabJson $ManifestPath $m
            return
        }
        $keyPath = Join-Path $stateRoot 'runner-key'
        if (-not (Test-Path $keyPath)) {
            & ssh-keygen -q -t rsa -b 4096 -f $keyPath -N ''
            if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' }
        }
        $m.sshKeyPath = $keyPath
        $parameters = @{
            location = $script:LabLocation
            labSubscriptionId = $script:LabSubscription
            networkResourceGroupName = $script:LabGroups[0]
            workloadResourceGroupName = $script:LabGroups[1]
            operationsResourceGroupName = $script:LabGroups[2]
            runnerSshPublicKey = (Get-Content "$keyPath.pub" -Raw).Trim()
            postgresqlAdministratorPassword = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)) + 'a!7'
            deploymentInstanceId = $m.deploymentInstanceId
            prerequisitePrincipalIds = Get-LabPrerequisitePrincipalIds $m
        }
        Invoke-LabDeployment $m $ManifestPath $script:LabGroups[0] 'csl-infrastructure' `
            (Join-Path $script:LabRoot 'infra\main.bicep') $parameters | Out-Null
        $m.status = 'INFRASTRUCTURE_CREATED'
    } else {
        $w = $m.outputs['csl-infrastructure'].workload.value
        $o = $m.outputs['csl-infrastructure'].operations.value
        $sshOptions = @(Get-LabSshOptions $m $stateRoot)
        $sshArgs = $sshOptions + @('-p', [string]$TunnelPort, 'csloperator@127.0.0.1')
        if ($Step -eq 'Runner') {
            $config = @{
                SUBSCRIPTION_ID = $script:LabSubscription; DEPLOYMENT_ID = $m.deploymentInstanceId
                RUNNER_CLIENT_ID = $o.runnerClientId; MIGRATION_CLIENT_ID = $w.migrationClientId
                RUNTIME_PRINCIPAL_ID = $w.runtimePrincipalId; POSTGRES_HOST = $w.postgresHost
                REGISTRY_NAME = $w.registryName; REGISTRY_LOGIN_SERVER = $w.registryLoginServer
                VAULT_NAME = $w.vaultName; STORAGE_NAME = $o.storageName
                LOG_ANALYTICS_WORKSPACE_ID = $w.logAnalyticsCustomerId
            }
            Write-LabJson (Join-Path $stateRoot 'runner-config.json') $config
            $bundle = Join-Path $stateRoot 'source.zip'
            if (Test-Path $bundle) { Remove-Item -LiteralPath $bundle }
            $entries = @()
            foreach ($folder in @('src\Demo.Api', 'tests\load', 'scripts\runner')) {
                $entries += Get-ChildItem (Join-Path $script:LabRoot $folder) -Recurse -File |
                    Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }
            }
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
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, (Join-Path $stateRoot 'runner-config.json'), 'runner-config.json') | Out-Null
            } finally { $zip.Dispose() }
            & scp @sshOptions -P $TunnelPort $bundle 'csloperator@127.0.0.1:source.zip'
            if ($LASTEXITCODE -ne 0) { throw 'Private source transfer failed.' }
            $bootstrapSucceeded = $false
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                & ssh @sshArgs 'mkdir -p ~/csl && unzip -o source.zip -d ~/csl >/dev/null && cd ~/csl && bash scripts/runner/bootstrap.sh > bootstrap.log 2>&1'
                if ($LASTEXITCODE -eq 0) { $bootstrapSucceeded = $true; break }
                $bootstrapLog = & ssh @sshArgs 'tail -n 100 ~/csl/bootstrap.log'
                if ($LASTEXITCODE -ne 0) { throw 'Private bootstrap and subsequent diagnostic-log retrieval failed.' }
                $bootstrapLogPath = Join-Path $stateRoot "bootstrap-attempt-$attempt.log"
                Set-Content -LiteralPath $bootstrapLogPath -Value $bootstrapLog -Encoding utf8
                if (($bootstrapLog -join "`n") -notmatch 'Forbidden|AuthorizationFailed|AuthorizationPermissionMismatch|UNAUTHORIZED') {
                    throw "Private bootstrap failed with a non-propagation error. Inspect $bootstrapLogPath before retrying."
                }
                Write-Warning "Private bootstrap attempt $attempt encountered an authorization error; bounded retry for newly assigned permissions. Evidence: $bootstrapLogPath"
                if ($attempt -lt 6) { Start-Sleep 30 }
            }
            if (-not $bootstrapSucceeded) { throw 'Private bootstrap failed after bounded authorization retries; inspect the saved bootstrap-attempt logs.' }
            $digest = (& ssh @sshArgs 'cat ~/csl/image-digest.txt' | Select-Object -Last 1).Trim()
            if ($LASTEXITCODE -ne 0 -or $digest -notmatch '^sha256:[0-9a-f]{64}$') { throw 'Invalid image digest from the private runner.' }
            $m.imageDigest = $digest
            $m.status = 'PRIVATE_IMAGE_PUBLISHED'
        } elseif ($Step -eq 'Application') {
            $app = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-application' `
                (Join-Path $script:LabRoot 'infra\workload-app.bicep') @{
                    location = $script:LabLocation
                    applicationRepository = 'demo-api'; applicationImageDigest = $m.imageDigest
                    deploymentInstanceId = $m.deploymentInstanceId
                }
            $configPath = Join-Path $stateRoot 'runner-config.json'
            $config = Get-Content $configPath -Raw | ConvertFrom-Json -AsHashtable
            $config.API_FQDN = $app.applicationFqdn.value
            Write-LabJson $configPath $config
            & scp @sshOptions -P $TunnelPort $configPath 'csloperator@127.0.0.1:csl/runner-config.json'
            if ($LASTEXITCODE -ne 0) { throw 'Private app configuration transfer failed.' }
            & ssh @sshArgs 'cd ~/csl && pwsh -NoLogo -NoProfile -File scripts/runner/verify.ps1 > verification.log 2>&1'
            if ($LASTEXITCODE -ne 0) { throw 'Private API identity, DNS, persistence, or idempotency verification failed.' }
            $m.status = 'APPLICATION_CREATED'
        } else {
            & (Join-Path $PSScriptRoot 'Register-Controller.ps1') -ManifestPath $ManifestPath -TunnelPort $TunnelPort
            $m = Read-LabManifest $ManifestPath
        }
    }
    Write-LabJson $ManifestPath $m
    Write-Output "Build stage $Step completed. Manifest: $ManifestPath"
} finally { $lock.Dispose() }
