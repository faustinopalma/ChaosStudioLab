param([Parameter(Mandatory)][string] $OutputPath)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$config=Get-Content "$PSScriptRoot\..\..\runner-config.json" -Raw|ConvertFrom-Json
$dns=@{}
foreach($hostName in @($config.API_FQDN,$config.PRIVATE_API_FQDN,$config.POSTGRES_HOST,$config.REGISTRY_HOST,"$($config.VAULT_NAME).vault.azure.net")){
    $addresses=@([Net.Dns]::GetHostAddresses($hostName)|ForEach-Object IPAddressToString)
    $dns[$hostName]=$addresses
    $valid=if($hostName -eq $config.API_FQDN){$addresses.Count -eq 1 -and $addresses[0] -eq $config.EXPECTED_API_IP}
        elseif($hostName -eq $config.PRIVATE_API_FQDN){$addresses.Count -gt 0 -and -not @($addresses|Where-Object {$_ -notmatch '^10\.91\.[0-3]\.\d+$'}).Count}
        else{$addresses.Count -gt 0 -and -not @($addresses|Where-Object {$_ -notmatch '^10\.91\.10\.\d+$'}).Count}
    if(-not $valid){throw "Private DNS resolved outside the approved service subnet: $hostName"}
}
$nodes=& kubectl get nodes -o json|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw 'Private node inventory failed.'}
$pods=& kubectl -n csl get pods -l app=csl-api -o json|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw 'Private pod inventory failed.'}
$services=& kubectl -n csl get service api -o json|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw 'Private application service inventory failed.'}
$deployment=& kubectl -n csl get deployment api -o json|ConvertFrom-Json
if($LASTEXITCODE -ne 0){throw 'Private application deployment inventory failed.'}
$apiEnvironment=$deployment.spec.template.spec.containers[0].env
if(@($apiEnvironment|Where-Object {$_.name -eq 'Kestrel__EndpointDefaults__Protocols' -and $_.value -eq 'Http1'}).Count -ne 1 -or
    @($apiEnvironment|Where-Object {$_.name -eq 'Orders__CacheImmutableReads' -and $_.value -eq 'true'}).Count -ne 1){
    throw 'Actual AKS workload must enable the qualified HTTP/1.1 ingress and immutable confirmed-order read cache.'
}
$affinity=$deployment.spec.template.spec.PSObject.Properties['affinity']
if($null -eq $affinity -or @($affinity.Value.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution|Where-Object {
    $_.topologyKey -eq 'kubernetes.io/hostname' -and $_.labelSelector.matchLabels.app -eq 'csl-api'
}).Count -ne 1){throw 'Actual deployment must require one application pod per worker hostname.'}
if($nodes.items.Count -ne 9 -or $pods.items.Count -ne 6 -or
    @($nodes.items|Where-Object {@($_.status.conditions|Where-Object {$_.type -eq 'Ready' -and $_.status -eq 'True'}).Count -ne 1}).Count -or
    @($pods.items|Where-Object {$_.status.phase -ne 'Running' -or @($_.status.containerStatuses|Where-Object {-not $_.ready}).Count}).Count){
    throw 'Require nine Ready nodes and six Ready application pods before measurement.'
}
if($services.spec.type -ne 'LoadBalancer' -or $services.metadata.annotations.'service.beta.kubernetes.io/azure-load-balancer-internal' -ne 'true' -or
    $services.status.loadBalancer.ingress[0].ip -ne $config.EXPECTED_API_IP){throw 'Actual application ingress is not the approved private load balancer.'}
if($services.spec.externalTrafficPolicy -ne 'Local' -or $services.spec.healthCheckNodePort -lt 30000 -or
    $services.metadata.annotations.'service.beta.kubernetes.io/azure-load-balancer-health-probe-interval' -ne '5' -or
    $services.metadata.annotations.'service.beta.kubernetes.io/azure-load-balancer-health-probe-num-of-probe' -ne '2'){
    throw 'Actual private ingress must use node-local routing and five-second/two-probe health checks.'
}
$placement=@(foreach($pod in $pods.items){
    $node=@($nodes.items|Where-Object {$_.metadata.name -eq $pod.spec.nodeName})
    if($node.Count -ne 1){throw 'Pod placement has an ambiguous node.'}
    @{uid=$pod.metadata.uid;pod=$pod.metadata.name;node=$node[0].metadata.name;zone=$node[0].metadata.labels.'topology.kubernetes.io/zone'
        providerId=$node[0].spec.providerID;image=$pod.spec.containers[0].image}
})
if(@($placement.node|Sort-Object -Unique).Count -ne 6 -or @($placement.zone|Sort-Object -Unique).Count -ne 3 -or
    @($placement|Where-Object {$_.image -notmatch '@sha256:[0-9a-f]{64}$'}).Count){throw 'Require six distinct workers across three observed zones and digest-pinned images.'}
$journal="$PSScriptRoot\..\..\results\private-verification-writes.ndjson"
$seed=@(Get-Content $journal|ForEach-Object {$_|ConvertFrom-Json}|Where-Object acknowledged)[-1]
& az login --identity --client-id $config.RUNNER_CLIENT_ID --allow-no-subscriptions -o none
if($LASTEXITCODE -ne 0){throw 'Private qualification identity login failed.'}
$token=& az keyvault secret show --vault-name $config.VAULT_NAME --name diagnostics-token --query value -o tsv
if($LASTEXITCODE -ne 0 -or -not $token){throw 'Private qualification secret retrieval failed.'}
$observations=[Collections.Generic.List[object]]::new()
$deadline=[DateTimeOffset]::UtcNow.AddMinutes(5)
try{
    do{
        foreach($kind in @('health','business','read-cache')){
            $url=switch($kind){
                'health' {"https://$($config.API_FQDN)/health/live"}
                'business' {"https://$($config.API_FQDN)/api/orders/$($seed.operationId)"}
                'read-cache' {"https://$($config.API_FQDN)/diagnostics/read-cache"}
            }
            $args=@{Uri=$url;TimeoutSec=10;Headers=@{Connection='close';'X-Run-Id'='aks-qualification'}}
            if($kind -ne 'health'){$args.Headers.Authorization="Bearer $token"}
            $response=Invoke-WebRequest @args
            if($response.BaseResponse.Version.ToString() -ne '1.1'){throw 'Actual private application traffic did not use the qualified HTTP/1.1 protocol.'}
            $uid=[string]($response.Headers['X-Lab-Instance-Id']|Select-Object -First 1)
            $processId=[string]($response.Headers['X-Lab-Process-Id']|Select-Object -First 1)
            $processStart=[string]($response.Headers['X-Lab-Process-Start-Utc']|Select-Object -First 1)
            $body=$response.Content|ConvertFrom-Json
            if($response.StatusCode -ne 200 -or $uid -notin $placement.uid){throw 'Traffic identity does not match current six pod UIDs.'}
            if($processId -notmatch '^\d+$' -or -not $processStart){throw 'Actual application process identity is incomplete.'}
            if($kind -eq 'health' -and ($body.status -ne 'live' -or $body.instanceId -ne $uid -or
                $body.processId -ne [int]$processId -or $body.revision -ne $config.SOURCE_REVISION)){
                throw 'Actual application health/source/process identity is inconsistent.'
            }
            if($kind -eq 'business' -and ($body.payloadSha256 -cne $seed.expectedChecksum -or $body.operationId -ne $seed.operationId)){throw 'Private business checksum participation failed.'}
            if($kind -eq 'read-cache' -and (-not $body.enabled -or $body.entries -lt 0 -or $body.entries -gt 10000)){
                throw 'Actual per-pod immutable read-cache configuration/capacity is unqualified.'
            }
            $observations.Add(@{kind=$kind;uid=$uid;processId=$processId;processStartedAtUtc=$processStart
                httpProtocol=$response.BaseResponse.Version.ToString();cache=if($kind -eq 'read-cache'){$body}else{$null};observedAtUtc=[DateTimeOffset]::UtcNow.ToString('O')})
        }
        $complete=@($placement|Where-Object {$p=$_;@($observations|Where-Object {$_.uid -eq $p.uid -and $_.kind -eq 'health'}).Count -and
            @($observations|Where-Object {$_.uid -eq $p.uid -and $_.kind -eq 'business'}).Count -and
            @($observations|Where-Object {$_.uid -eq $p.uid -and $_.kind -eq 'read-cache'}).Count}).Count -eq 6
    }while(-not $complete -and [DateTimeOffset]::UtcNow -lt $deadline)
    if(-not $complete){throw 'Five-minute participation qualification did not observe health and business traffic from every pod.'}
    @{status='PASS';placement=$placement;observations=$observations.ToArray();nodes=$nodes;pods=$pods;service=$services;deployment=$deployment;dns=$dns}|
        ConvertTo-Json -Depth 40|Set-Content -LiteralPath $OutputPath
    'CSL_AKS_PLACEMENT_QUALIFIED'
}finally{$token=$null}
