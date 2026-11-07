[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $ManifestPath,
    [Parameter(Mandatory)][ValidateSet('Scope','Identities','Infrastructure','Access','Runner','Application','Native')][string] $Step,
    [int] $TunnelPort = 50222
)
. (Join-Path $PSScriptRoot 'Lab.Aks.ps1')
Confirm-LabContext
$m = Read-LabManifest $ManifestPath
$root = Split-Path ([IO.Path]::GetFullPath($ManifestPath)) -Parent
Assert-LabBuildValidation $Step ((Get-Content (Join-Path $script:LabRoot '.azure\deployment-plan.md') -Raw) -split '## Historical App Service plan')[0]
$lock = [IO.File]::Open("$ManifestPath.lock", 'OpenOrCreate', 'ReadWrite', 'None')
$started = [DateTimeOffset]::UtcNow
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
        $preview = Invoke-LabAz @('deployment','sub','what-if','--location',$script:LabLocation,'--template-file',"$script:LabRoot\infra\scope.bicep",'--parameters',"@$parameterPath",'--no-pretty-print','-o','json') | ConvertFrom-Json -AsHashtable
        Write-LabJson "$root\scope.what-if.json" $preview
        foreach ($c in $preview.changes) {
            if ($c.resourceId -notin $m.groups.id -and $c.resourceId -ne $ex.id) { throw 'Scope preview includes an unexpected resource.' }
            if ($c.changeType -ne 'Create') { throw 'Scope preview is not a fresh creation.' }
        }
        Invoke-LabAz @('deployment','sub','create','--name',"csl-aks-scope-$($m.deploymentInstanceId.Substring(0,8))",'--location',$script:LabLocation,'--template-file',"$script:LabRoot\infra\scope.bicep",'--parameters',"@$parameterPath",'-o','json') | Out-Null
    } else {
        Assert-LabPolicyExemptions $m
        if ($Step -eq 'Identities') {
            $m.outputs.identities = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aks-identities' "$script:LabRoot\infra\modules\aks-identities.bicep" @{location=$script:LabLocation;deploymentInstanceId=$m.deploymentInstanceId}
        } elseif ($Step -eq 'Infrastructure') {
            $ids = $m.outputs.identities.identities.value
            $principals = @{}
            foreach ($entry in @{runtime='id-csl-runtime'; migration='id-csl-migrations';chaos='id-csl-chaos';control='id-csl-aks';kubelet='id-csl-kubelet'}.GetEnumerator()) {
                $principals[$entry.Key] = ($ids | Where-Object name -eq $entry.Value).principalId
            }
            $principals.kubeletClient = ($ids | Where-Object name -eq 'id-csl-kubelet').clientId
            $key = "$root\runner-key"
            if (-not (Test-Path $key)) { & ssh-keygen -q -t rsa -b 4096 -f $key -N ''; if ($LASTEXITCODE -ne 0) { throw 'SSH key generation failed.' } }
            $m.sshKeyPath = $key
            $m.outputs.infrastructure = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[0] 'csl-aks-infrastructure' "$script:LabRoot\infra\aks-main.bicep" @{
                location=$script:LabLocation;deploymentInstanceId=$m.deploymentInstanceId
                networkResourceGroupName=$script:LabGroups[0]; workloadResourceGroupName=$script:LabGroups[1]
                operationsResourceGroupName=$script:LabGroups[2];nodeResourceGroupName=$script:LabGroups[3]
                prerequisitePrincipalIds=$principals;runnerSshPublicKey=(Get-Content "$key.pub" -Raw).Trim()
                kubernetesVersion='1.35.9';postgresqlAdministratorPassword=([Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))+'a!7')
            }
            $w = $m.outputs.infrastructure.workload.value
            $actual = Invoke-LabAz @('aks','show','-g',$script:LabGroups[1],'-n',$w.clusterName,'-o','json') | ConvertFrom-Json -AsHashtable
            if ($actual.nodeResourceGroup -ne $script:LabGroups[3] -or $actual.tags.deploymentInstanceId -ne $m.deploymentInstanceId) { throw 'Managed node group linkage mismatch.' }
            Invoke-LabAz @('group','update','-n',$script:LabGroups[3],'--set',"tags.project=ChaosStudioLab","tags.labId=lab-dev01","tags.deploymentInstanceId=$($m.deploymentInstanceId)",'-o','none') | Out-Null
            $m.managedNodeGroupVerified = $true
        } elseif ($Step -eq 'Access') {
            $w=$m.outputs.infrastructure.workload.value; $o=$m.outputs.infrastructure.operations.value
            $m.outputs.access = Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aks-access' "$script:LabRoot\infra\aks-access.bicep" @{
                runnerPrincipalId=$o.runnerPrincipalId;chaosPrincipalId=$w.chaosPrincipalId;clusterName=$w.clusterName
                registryName=$w.registryName;vaultName=$w.vaultName;postgresName=$w.postgresName
            }
            $zones=@(Invoke-LabAz @('network','private-dns','zone','list','-g',$script:LabGroups[3],'-o','json')|ConvertFrom-Json -AsHashtable)
            if ($zones.Count -ne 1) { throw 'Private AKS API DNS zone is ambiguous.' }
            $m.outputs.nodeAccess=Invoke-LabDeployment $m $ManifestPath $script:LabGroups[3] 'csl-aks-node-access' "$script:LabRoot\infra\aks-node-access.bicep" @{
                chaosPrincipalId=$w.chaosPrincipalId;runnerPrincipalId=$o.runnerPrincipalId
                privateApiZoneName=$zones[0].name;operationsVnetId=$o.vnetId
            }
        } elseif ($Step -eq 'Runner') {
            $o=$m.outputs.infrastructure.operations.value
            $scriptBody=(Get-Content "$script:LabRoot\scripts\runner\install.sh" -Raw).Replace("`r`n","`n")
            $extra=(Get-Content "$script:LabRoot\scripts\runner\install-aks.sh" -Raw).Replace("`r`n","`n").Replace('bash "$(dirname "$0")/install.sh"','')
            $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($scriptBody+"`n"+$extra))
            $result=Invoke-LabAz @('vm','run-command','invoke','-g',$script:LabGroups[2],'-n','vm-csl-runner','--command-id','RunShellScript','--scripts',"printf '%s' '$encoded' | base64 -d > /tmp/csl-install-aks.sh; timeout 1200 bash /tmp/csl-install-aks.sh",'-o','json')|ConvertFrom-Json -AsHashtable
            Write-LabJson "$root\runner-install.json" $result
            if (($result.value.message -join "`n") -notmatch 'CSL_AKS_INSTALL_COMPLETED') { throw 'Runner install did not reach its success marker.' }
        } elseif ($Step -eq 'Application') {
            $w=$m.outputs.infrastructure.workload.value; $o=$m.outputs.infrastructure.operations.value
            $revision=(& git -C $script:LabRoot rev-parse HEAD).Trim()
            $m.sourceRevision=$revision
            $config=@{SUBSCRIPTION_ID=$script:LabSubscription;RUNNER_CLIENT_ID=$o.runnerClientId;MIGRATION_CLIENT_ID=$w.migrationClientId;RUNTIME_PRINCIPAL_ID=$w.runtimePrincipalId
                RUNTIME_CLIENT_ID=$w.runtimeClientId;POSTGRES_HOST=$w.postgresHost;VAULT_NAME=$w.vaultName;API_FQDN=$w.apiFqdn;CLUSTER_NAME=$w.clusterName
                APP_RESOURCE_GROUP=$script:LabGroups[1];NODE_RESOURCE_GROUP=$script:LabGroups[3];REGISTRY_NAME=$w.registryName;REGISTRY_HOST=$w.registryHost;SOURCE_REVISION=$revision
                EXPECTED_API_IP='10.91.3.240';PRIVATE_API_FQDN=$w.privateFqdn;ARCHITECTURE='private-aks'}
            Write-LabJson "$root\runner-config.json" $config
            $archive="$root\aks-source.zip"; if(Test-Path $archive){Remove-Item -LiteralPath $archive}
            $zip=[IO.Compression.ZipFile]::Open($archive,[IO.Compression.ZipArchiveMode]::Create)
            try {
                foreach($folder in @('src\Demo.Api','scripts\runner','tests\load','k8s')){
                    foreach($file in Get-ChildItem "$script:LabRoot\$folder" -Recurse -File|Where-Object FullName -NotMatch '\\(bin|obj)\\'){
                        $relative=[IO.Path]::GetRelativePath($script:LabRoot,$file.FullName).Replace('\','/')
                        $writer=[IO.StreamWriter]::new($zip.CreateEntry($relative).Open(),[Text.UTF8Encoding]::new($false))
                        try{$writer.Write([IO.File]::ReadAllText($file.FullName).Replace("`r`n","`n"))}finally{$writer.Dispose()}
                    }
                }
                [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip,"$root\runner-config.json",'runner-config.json')|Out-Null
            }finally{$zip.Dispose()}
            $m.sourceBundleSha256=(Get-FileHash $archive).Hash.ToLowerInvariant()
            $options=@(Get-LabSshOptions $m $root)
            & scp @options -P $TunnelPort $archive csloperator@127.0.0.1:aks-source.zip
            if($LASTEXITCODE -ne 0){throw 'Source bundle transfer failed.'}
            Invoke-AksPrivate $m $root "printf '%s  aks-source.zip\n' '$($m.sourceBundleSha256)' | sha256sum -c; mkdir -p ~/csl; unzip -oq aks-source.zip -d ~/csl; cd ~/csl; timeout 1800 bash scripts/runner/bootstrap-aks.sh" $TunnelPort
            & scp @options -P $TunnelPort csloperator@127.0.0.1:csl/image-digest.txt "$root\image-digest.txt"
            if($LASTEXITCODE -ne 0){throw 'Actual deployed application digest retrieval failed.'}
            $digest=(Get-Content "$root\image-digest.txt" -Raw).Trim()
            if($digest -notmatch ('^'+[regex]::Escape($w.registryHost)+'/csl-api@sha256:[0-9a-f]{64}$')){
                throw 'Actual deployed image digest is not from the exact private registry/repository.'
            }
            $m.applicationImageDigest=$digest
            $m.Remove('lastBaseline')
            & scp @options -P $TunnelPort csloperator@127.0.0.1:csl/k8s/application-preview.diff "$root\application-preview.diff"
            if($LASTEXITCODE -ne 0){throw 'Exact owned Kubernetes application preview retrieval failed.'}
        } elseif ($Step -eq 'Native') {
            $w=$m.outputs.infrastructure.workload.value
            $sets=Invoke-LabAz @('vmss','list','-g',$script:LabGroups[3],'-o','json')|ConvertFrom-Json -AsHashtable
            $single=@($sets|Where-Object {$_.tags.'aks-managed-poolName' -eq 'z1a'})
            if($single.Count -ne 1 -or $single[0].sku.capacity -ne 1 -or $sets.Count -ne 7){throw 'Expected seven node pools and an exact single-node target.'}
            $zoneSets=@($sets|Where-Object {$_.tags.'aks-managed-poolName' -in @('system','z1a','z1b')})
            if($zoneSets.Count -ne 3){throw 'Selected zone must include its system pool and both user pools.'}
            $m.nativeTargets=@{single=$single[0].id;zone=@($zoneSets.id);logicalZone='1'}
            $m.outputs.native=Invoke-LabDeployment $m $ManifestPath $script:LabGroups[1] 'csl-aks-native' "$script:LabRoot\infra\aks-native-scenarios.bicep" @{
                location=$script:LabChaosLocation;deploymentInstanceId=$m.deploymentInstanceId;workspaceName="csl-aks-chaos-$($m.deploymentInstanceId.Substring(0,8))"
                chaosIdentityId=$w.chaosIdentityId;scopes=@($m.groups[1].id,$m.groups[3].id);exactNodeScaleSetId=$single[0].id
                zoneScaleSetIds=@($zoneSets.id);selectedLogicalZone='1';postgresResourceId=$w.postgresId
            }
        }
    }
    $m.status="AKS_$($Step.ToUpperInvariant())_COMPLETE"
} finally {
    $m.lastStage=@{step=$Step;startedAtUtc=$started.ToString('O');finishedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')}
    if(-not $m.ContainsKey('stageTimings')){$m.stageTimings=@()}
    $m.stageTimings+=@($m.lastStage.Clone())
    Save-LabInventory $m $ManifestPath
    $lock.Dispose()
}
