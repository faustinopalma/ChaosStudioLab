param([Parameter(Mandatory)][string] $OutputPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$c=Get-Content "$PSScriptRoot\..\..\runner-config.json" -Raw|ConvertFrom-Json
$api='2026-07-01'
$dns=@{}
foreach($hostName in @($c.API_FQDN,$c.POSTGRES_HOST,$c.REGISTRY_HOST,"$($c.VAULT_NAME).vault.azure.net",$c.SHARED_CACHE_HOST)){
    $addresses=@([Net.Dns]::GetHostAddresses($hostName)|ForEach-Object IPAddressToString)
    $dns[$hostName]=$addresses
    $valid=if($hostName -eq $c.API_FQDN){$addresses.Count -eq 1 -and $addresses[0] -eq $c.EXPECTED_API_IP}
        else{$addresses.Count -gt 0 -and -not @($addresses|Where-Object {$_ -notmatch '^10\.96\.10\.\d+$'}).Count}
    if(-not $valid){throw "Private DNS resolved outside the approved address: $hostName"}
}
& az login --identity --client-id $c.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if($LASTEXITCODE -ne 0){throw 'Private qualification identity login failed.'}
$base="https://management.azure.com/subscriptions/$($c.SUBSCRIPTION_ID)/resourceGroups/$($c.APP_RESOURCE_GROUP)/providers/Microsoft.App"
function Get-Arm([string]$Path){$r=& az rest --method get --url "$base/$Path`?api-version=$api" -o json;if($LASTEXITCODE -ne 0){throw "ARM read failed: $Path"};$r|ConvertFrom-Json}
$environment=Get-Arm "managedEnvironments/$($c.ENVIRONMENT_NAME)"
$app=Get-Arm "containerApps/$($c.APP_NAME)"
$p=$environment.properties
if(-not $p.zoneRedundant -or -not $p.vnetConfiguration.internal -or $p.staticIp -ne $c.EXPECTED_API_IP -or $p.publicNetworkAccess -ne 'Disabled'){
    throw 'Environment must be zone-redundant, internal and private with the approved static IP.'
}
$a=$app.properties
$container=$a.template.containers[0]
$settings=@{};foreach($e in $container.env){$settings[$e.name]=if($e.PSObject.Properties['value']){$e.value}else{"secretRef:$($e.secretRef)"}}
$readiness=@($container.probes|Where-Object type -eq 'Readiness')
if($a.configuration.activeRevisionsMode -ne 'Single' -or $a.template.scale.minReplicas -ne 6 -or $a.template.scale.maxReplicas -ne 6 -or
    $container.image -notmatch '@sha256:[0-9a-f]{64}$' -or $a.configuration.ingress.transport -ne 'http' -or -not $a.configuration.ingress.external -or
    $readiness.Count -ne 1 -or $readiness[0].httpGet.path -ne '/health/serving' -or $settings['Orders__CacheImmutableReads'] -ne 'true' -or
    $settings['Orders__SharedCacheHost'] -ne $c.SHARED_CACHE_HOST -or $settings['Diagnostics__Token'] -ne 'secretRef:diagnostics-token' -or
    $a.latestReadyRevisionName -ne $a.latestRevisionName -or $a.provisioningState -ne 'Succeeded'){
    throw 'Container app configuration differs from the qualified fixed six-replica, digest-pinned, cached private contract.'
}
$replicas=@((Get-Arm "containerApps/$($c.APP_NAME)/revisions/$($a.latestRevisionName)/replicas").value)
$names=@($replicas|ForEach-Object name)
if($replicas.Count -ne 6 -or @($replicas|Where-Object {$_.properties.runningState -ne 'Running' -or @($_.properties.containers|Where-Object {-not $_.PSObject.Properties['ready'] -or -not $_.ready}).Count}).Count){
    throw 'Require exactly six Running replicas with ready containers before measurement.'
}
$journal="$PSScriptRoot\..\..\results\private-verification-writes.ndjson"
$seed=@(Get-Content $journal|ForEach-Object {$_|ConvertFrom-Json}|Where-Object acknowledged)[-1]
$token=& az keyvault secret show --vault-name $c.VAULT_NAME --name diagnostics-token --query value -o tsv
if($LASTEXITCODE -ne 0 -or -not $token){throw 'Private qualification secret retrieval failed.'}
$observations=[Collections.Generic.List[object]]::new()
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(5)
try{
    do{
        foreach($kind in @('health','business','read-cache')){
            $url=switch($kind){'health'{"https://$($c.API_FQDN)/health/live"}'business'{"https://$($c.API_FQDN)/api/orders/$($seed.operationId)"}'read-cache'{"https://$($c.API_FQDN)/diagnostics/read-cache"}}
            $request=@{Uri=$url;TimeoutSec=10;Headers=@{Connection='close';'X-Run-Id'='aca-qualification'}}
            if($kind -ne 'health'){$request.Headers.Authorization="Bearer $token"}
            $response=Invoke-WebRequest @request
            $replica=[string]($response.Headers['X-Lab-Instance-Id']|Select-Object -First 1)
            $body=$response.Content|ConvertFrom-Json
            if($response.StatusCode -ne 200 -or $replica -notin $names){throw 'Traffic identity does not match the six current replicas.'}
            if($kind -eq 'health' -and ($body.status -ne 'live' -or $body.revision -ne $c.SOURCE_REVISION)){throw 'Replica health/source identity is inconsistent.'}
            if($kind -eq 'business' -and ($body.payloadSha256 -cne $seed.expectedChecksum -or $body.operationId -ne $seed.operationId)){throw 'Private business checksum participation failed.'}
            if($kind -eq 'read-cache' -and (-not $body.enabled -or -not $body.shared.enabled -or -not $body.shared.connected)){throw 'Replica confirmed-order cache is unqualified.'}
            $observations.Add(@{kind=$kind;replica=$replica;processId=[string]($response.Headers['X-Lab-Process-Id']|Select-Object -First 1)
                httpProtocol=$response.BaseResponse.Version.ToString();observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')})
        }
        $complete=@($names|Where-Object {$n=$_;@($observations|Where-Object {$_.replica -eq $n}|ForEach-Object kind|Sort-Object -Unique).Count -eq 3}).Count -eq 6
    }while(-not $complete -and [DateTimeOffset]::UtcNow -lt $deadline)
    if(-not $complete){throw 'Five-minute participation qualification did not observe health, business and cache traffic from every replica.'}
    @{status='PASS';revision=$a.latestRevisionName;replicas=$replicas;observations=$observations.ToArray();dns=$dns
        environment=@{zoneRedundant=$p.zoneRedundant;internal=$p.vnetConfiguration.internal;staticIp=$p.staticIp;workloadProfiles=$p.workloadProfiles}
        app=@{image=$container.image;scale=$a.template.scale;probes=$container.probes;ingressTransport=$a.configuration.ingress.transport}
        replicaZonePlacement='platform-managed; Container Apps exposes no per-replica zone'}|
        ConvertTo-Json -Depth 40|Set-Content -LiteralPath $OutputPath
    'CSL_ACA_PLACEMENT_QUALIFIED'
}finally{$token=$null}
