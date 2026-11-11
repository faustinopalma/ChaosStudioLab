[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][ValidateSet('Scope','Identities','Infrastructure','EnvironmentDns','Access','Runner','Application','Native')][string] $Step,
    [int] $TunnelPort = 40222
)
. (Join-Path $PSScriptRoot 'Lab.Aca.ps1')
Confirm-LabContext
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
$m = Read-LabManifest $ManifestPath
$root = Split-Path $ManifestPath -Parent
Assert-LabBuildValidation $Step ((Get-Content (Join-Path $script:LabRoot '.azure\deployment-plan.md') -Raw) -split '## Superseded')[0]
$lock = [IO.File]::Open("$ManifestPath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
$started = [DateTimeOffset]::UtcNow
$infra = "$script:LabRoot\infra"
try {
    if ($Step -eq 'Scope') {
        foreach ($group in $m.groups[0..2]) {
            if ((Invoke-LabAz @('group','exists','-n',$group.name,'-o','tsv')) -ne 'false') { throw 'Scope already exists; inspect before retrying.' }
        }
        $ex = $m.policyExemptions[0]
        $params = @{location=$script:LabLocation; deploymentInstanceId=$m.deploymentInstanceId; resourceGroupNames=$script:LabGroups[0..2]
            policyAssignmentId=$ex.assignmentId; policyReferenceId=$ex.referenceIds[0]; exemptionName=($ex.id -split '/')[-1]
            exemptionExpiresOn=$script:LabEnvironment.exemptionExpiresOn}
        $parameterPath = "$root\scope.parameters.json"
        $arm = @{}; foreach ($key in $params.Keys) { $arm[$key] = @{value=$params[$key]} }
        Write-LabJson $parameterPath @{parameters=$arm}
        $preview = Invoke-LabAz @('deployment','sub','what-if','--location',$script:LabLocation,'--template-file',"$infra\scope.bicep",'--parameters',"@$parameterPath",'--no-pretty-print','-o','json') | ConvertFrom-Json -AsHashtable
        Write-LabJson "$root\scope.what-if.json" $preview
        foreach ($c in $preview.changes) {
            if ($c.resourceId -notin $m.groups.id -and $c.resourceId -ne $ex.id) { throw 'Scope preview includes an unexpected resource.' }
            if ($c.changeType -ne 'Create') { throw 'Scope preview is not a fresh creation.' }
        }
        Invoke-LabAz @('deployment','sub','create','--name',"csl-aca-scope-$($m.deploymentInstanceId.Substring(0,8))",'--location',$script:LabLocation,'--template-file',"$infra\scope.bicep",'--parameters',"@$parameterPath",'-o','json') | Out-Null
    } else {
        Assert-LabPolicyExemptions $m
        if ($Step -eq 'Identities') {
            $m.outputs.identities = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aca-identities' "$infra\modules\aks-identities.bicep" @{
                location=$script:LabLocation; deploymentInstanceId=$m.deploymentInstanceId; names=@('id-csl-runtime','id-csl-migrations','id-csl-chaos')
            }
        } elseif ($Step -eq 'Infrastructure') {
            $ids = $m.outputs.identities.identities.value
            $principals = @{}
            foreach ($entry in @{runtime='id-csl-runtime'; migration='id-csl-migrations'; chaos='id-csl-chaos'}.GetEnumerator()) {
                $principals[$entry.Key] = ($ids | Where-Object name -eq $entry.Value).principalId
            }
            $key = "$root\runner-key"
            if (-not (Test-Path $key)) { & ssh-keygen -q -t rsa -b 4096 -f $key -N ''; if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' } }
            $m.sshKeyPath = $key
            $m.outputs.infrastructure = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[0] 'csl-aca-infrastructure' "$infra\aca-main.bicep" @{
                location=$script:LabLocation; deploymentInstanceId=$m.deploymentInstanceId
                networkResourceGroupName=$script:LabGroups[0]; workloadResourceGroupName=$script:LabGroups[1]
                operationsResourceGroupName=$script:LabGroups[2]; infrastructureResourceGroupName=$script:LabGroups[3]
                prerequisitePrincipalIds=$principals; runnerSshPublicKey=(Get-Content "$key.pub" -Raw).Trim()
                postgresqlAdministratorPassword=([Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))+'a!7')
            }
            $w = $m.outputs.infrastructure.workload.value
            $environment = Invoke-LabAz @('resource','show','--ids',$w.environmentId,'-o','json') | ConvertFrom-Json -AsHashtable
            if ($environment.properties.infrastructureResourceGroup -ne $script:LabGroups[3] -or $environment.tags.deploymentInstanceId -ne $m.deploymentInstanceId -or
                -not $environment.properties.zoneRedundant -or -not $environment.properties.vnetConfiguration.internal) {
                throw 'Container Apps environment linkage, zone redundancy or internal ingress differs from the plan.'
            }
            Invoke-LabAz @('group','update','-n',$script:LabGroups[3],'--set','tags.project=ChaosStudioLab','tags.labId=lab-dev01',"tags.deploymentInstanceId=$($m.deploymentInstanceId)",'-o','none') | Out-Null
            $m.managedInfrastructureGroupVerified = $true
        } elseif ($Step -eq 'EnvironmentDns') {
            $w = $m.outputs.infrastructure.workload.value; $o = $m.outputs.infrastructure.operations.value
            $m.outputs.environmentDns = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[0] 'csl-aca-environment-dns' "$infra\modules\aca-environment-dns.bicep" @{
                defaultDomain=$w.defaultDomain; staticIp=$w.staticIp; vnetIds=@($w.vnetId,$o.vnetId); deploymentInstanceId=$m.deploymentInstanceId
            }
        } elseif ($Step -eq 'Access') {
            $w = $m.outputs.infrastructure.workload.value; $o = $m.outputs.infrastructure.operations.value
            $m.outputs.access = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aca-access' "$infra\aca-access.bicep" @{
                runnerPrincipalId=$o.runnerPrincipalId; chaosPrincipalId=$w.chaosPrincipalId
                registryName=$w.registryName; vaultName=$w.vaultName; postgresName=$w.postgresName
            }
        } elseif ($Step -eq 'Runner') {
            $body = (Get-Content "$script:LabRoot\scripts\runner\install.sh" -Raw).Replace("`r`n","`n")
            $extra = (Get-Content "$script:LabRoot\scripts\runner\install-aca.sh" -Raw).Replace("`r`n","`n").Replace('bash "$(dirname "$0")/install.sh"','')
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($body + "`n" + $extra))
            $result = Invoke-LabAz @('vm','run-command','invoke','-g',$script:LabGroups[2],'-n','vm-csl-runner','--command-id','RunShellScript','--scripts',"printf '%s' '$encoded' | base64 -d > /tmp/csl-install-aca.sh; timeout 1200 bash /tmp/csl-install-aca.sh",'-o','json') | ConvertFrom-Json -AsHashtable
            Write-LabJson "$root\runner-install.json" $result
            if (($result.value.message -join "`n") -notmatch 'CSL_ACA_INSTALL_COMPLETED') { throw 'Runner install did not reach its success marker.' }
        } elseif ($Step -eq 'Application') {
            $w = $m.outputs.infrastructure.workload.value; $o = $m.outputs.infrastructure.operations.value
            $cache = $m.outputs.infrastructure.readCache.value
            $revision = (& git -C $script:LabRoot rev-parse HEAD).Trim()
            $m.sourceRevision = $revision
            $config = [ordered]@{SUBSCRIPTION_ID=$script:LabSubscription; RUNNER_CLIENT_ID=$o.runnerClientId; MIGRATION_CLIENT_ID=$w.migrationClientId
                RUNTIME_PRINCIPAL_ID=$w.runtimePrincipalId; RUNTIME_CLIENT_ID=$w.runtimeClientId; POSTGRES_HOST=$w.postgresHost; VAULT_NAME=$w.vaultName
                API_FQDN=$w.apiFqdn; APP_NAME=$w.appName; APP_RESOURCE_GROUP=$script:LabGroups[1]; ENVIRONMENT_NAME=$w.environmentName
                REGISTRY_NAME=$w.registryName; REGISTRY_HOST=$w.registryHost; SOURCE_REVISION=$revision; EXPECTED_API_IP=$w.staticIp
                ARCHITECTURE='private-aca'; SHARED_CACHE_HOST=$cache.host}
            Write-LabJson "$root\runner-config.json" $config
            $tokenPath = "$root\diagnostics-token.txt"
            if (-not (Test-Path $tokenPath)) {
                [IO.File]::WriteAllText($tokenPath, [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLowerInvariant())
            }
            $archive = "$root\aca-source.zip"; if (Test-Path $archive) { Remove-Item -LiteralPath $archive }
            $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach ($folder in @('src\Demo.Api','scripts\runner','tests\load')) {
                    foreach ($file in Get-ChildItem "$script:LabRoot\$folder" -Recurse -File | Where-Object FullName -NotMatch '\\(bin|obj)\\') {
                        $relative = [IO.Path]::GetRelativePath($script:LabRoot, $file.FullName).Replace('\','/')
                        $writer = [IO.StreamWriter]::new($zip.CreateEntry($relative).Open(), [Text.UTF8Encoding]::new($false))
                        try { $writer.Write([IO.File]::ReadAllText($file.FullName).Replace("`r`n","`n")) } finally { $writer.Dispose() }
                    }
                }
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, "$root\runner-config.json", 'runner-config.json') | Out-Null
            } finally { $zip.Dispose() }
            $m.sourceBundleSha256 = (Get-FileHash $archive).Hash.ToLowerInvariant()
            $options = @(Get-LabSshOptions $m $root)
            & scp @options -P $TunnelPort $archive $tokenPath csloperator@127.0.0.1:
            if ($LASTEXITCODE -ne 0) { throw 'Source bundle transfer failed.' }
            Invoke-AcaPrivate $m $root "chmod 600 diagnostics-token.txt; printf '%s  aca-source.zip\n' '$($m.sourceBundleSha256)' | sha256sum -c; mkdir -p ~/csl; unzip -oq aca-source.zip -d ~/csl; mv diagnostics-token.txt ~/csl/; cd ~/csl; timeout 2400 bash scripts/runner/bootstrap-aca.sh" $TunnelPort
            & scp @options -P $TunnelPort csloperator@127.0.0.1:csl/image-digest.txt "$root\image-digest.txt"
            if ($LASTEXITCODE -ne 0) { throw 'Published image digest retrieval failed.' }
            $digest = (Get-Content "$root\image-digest.txt" -Raw).Trim()
            if ($digest -notmatch ('^' + [regex]::Escape($w.registryHost) + '/csl-api@sha256:[0-9a-f]{64}$')) { throw 'Image digest is not from the exact private registry/repository.' }
            $m.applicationImageDigest = $digest
            $m.outputs.application = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aca-application' "$infra\aca-app.bicep" @{
                location=$script:LabLocation; deploymentInstanceId=$m.deploymentInstanceId; environmentId=$w.environmentId
                runtimeIdentityId=$w.runtimeIdentityId; runtimeClientId=$w.runtimeClientId; registryHost=$w.registryHost; imageReference=$digest
                postgresHost=$w.postgresHost; sharedCacheHost=$cache.host; sourceRevision=$revision
                diagnosticsToken=(Get-Content $tokenPath -Raw).Trim()
            }
            $m.Remove('lastBaseline')
            Invoke-AcaPrivate $m $root 'cd ~/csl && timeout 1200 pwsh -NoProfile -File scripts/runner/verify.ps1' $TunnelPort
        } elseif ($Step -eq 'Native') {
            $w = $m.outputs.infrastructure.workload.value
            $m.outputs.native = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aca-native' "$infra\aca-native-scenarios.bicep" @{
                location=$script:LabChaosLocation; deploymentInstanceId=$m.deploymentInstanceId; workspaceName="csl-aca-chaos-$($m.deploymentInstanceId.Substring(0,8))"
                chaosIdentityId=$w.chaosIdentityId; scopes=@($m.groups[1].id); postgresResourceId=$w.postgresId
            }
        }
    }
    $m.status = "ACA_$($Step.ToUpperInvariant())_COMPLETE"
} finally {
    $m.lastStage = @{step=$Step; startedAtUtc=$started.ToString('O'); finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}
    if (-not $m.ContainsKey('stageTimings')) { $m.stageTimings = @() }
    $m.stageTimings += @($m.lastStage.Clone())
    Save-LabInventory $m $ManifestPath
    $lock.Dispose()
}
Write-Output "$Step completed in $([Math]::Round(([DateTimeOffset]::UtcNow - $started).TotalSeconds)) s."
