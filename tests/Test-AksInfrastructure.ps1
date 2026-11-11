$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tmp = Join-Path ([IO.Path]::GetTempPath()) "csl-aks-test-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory $tmp | Out-Null
try {
    foreach ($name in @('aks-main','aks-read-cache','aks-app-dns','aks-native-scenarios','aks-access','aks-node-access','modules\aks-identities','modules\aks-workload')) {
        $file = Join-Path $tmp "$([IO.Path]::GetFileName($name)).json"
        & az bicep build --file "$root\infra\$name.bicep" --outfile $file --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "AKS Bicep compilation failed: $name" }
    }
    $w = Get-Content "$tmp\aks-workload.json" -Raw | ConvertFrom-Json -AsHashtable
    $main = Get-Content "$tmp\aks-main.json" -Raw | ConvertFrom-Json -AsHashtable
    $cacheTemplate = Get-Content "$tmp\aks-read-cache.json" -Raw | ConvertFrom-Json -AsHashtable
    $cacheResources = if ($cacheTemplate.resources -is [hashtable]) { @($cacheTemplate.resources.Values) } else { @($cacheTemplate.resources) }
    $cache = @($cacheResources | Where-Object { $_.name -eq 'csl-aks-shared-cache' -or $_.name -eq "[format('csl-{0}-shared-cache', parameters('labelPrefix'))]" })[0].properties.parameters
    if ($cacheTemplate.parameters.labelPrefix.defaultValue -ne 'aks') { throw 'The AKS shared-cache deployment must keep its aks default label.' }
    if ($cache.publicNetworkAccess.value -ne 'Disabled' -or $cache.highAvailability.value -ne 'Enabled' -or
        $cache.minimumTlsVersion.value -ne '1.2' -or $cache.enableTelemetry.value -or
        $cache.database.value.accessKeysAuthentication -ne 'Disabled' -or $cache.database.value.clientProtocol -ne 'Encrypted' -or
        $cache.database.value.port -ne 10000 -or $cache.database.value.accessPolicyAssignments.Count -ne 1 -or
        $cache.database.value.accessPolicyAssignments[0].userObjectId -ne "[parameters('runtimePrincipalId')]" -or
        $cache.privateEndpoints.value.Count -ne 1 -or
        @($cacheResources | Where-Object {$_.type -eq 'Microsoft.Network/privateDnsZones' -and $_.name -eq 'privatelink.redis.azure.net'}).Count -ne 1) {
        throw 'Shared managed cache requires private DNS/endpoint, HA, verified TLS, exact runtime Entra access and no keys/telemetry.'
    }
    $apiDns = @($main.resources | Where-Object name -eq 'csl-aks-api-dns')
    if ($apiDns.Count -ne 1 -or -not @($apiDns[0].dependsOn | Where-Object { $_ -like '*csl-aks-network*' }).Count) {
        throw 'Application private DNS must wait for its zone-creation deployment.'
    }
    $aks = @($w.resources | Where-Object type -EQ 'Microsoft.ContainerService/managedClusters')
    if ($aks.Count -ne 1 -or -not $aks[0].properties.apiServerAccessProfile.enablePrivateCluster -or
        $aks[0].properties.apiServerAccessProfile.enablePrivateClusterPublicFQDN -or
        -not $aks[0].properties.disableLocalAccounts -or -not $aks[0].properties.securityProfile.workloadIdentity.enabled -or
        $aks[0].properties.networkProfile.outboundType -ne 'userAssignedNATGateway' -or
        $aks[0].properties.networkProfile.networkPluginMode -ne 'overlay') { throw 'AKS private control-plane, identity or egress invariant failed.' }
    $profiles = Get-Content "$root\infra\modules\aks-workload.bicep" -Raw
    foreach ($zone in @('z1a','z1b','z2a','z2b','z3a','z3b')) { if ($profiles -notmatch "name: '$zone'") { throw 'Missing deterministic user pool.' } }
    if ($profiles -match 'enableAutoScaling: true') { throw 'Autoscaling invalidates the sustained fixed-node fault.' }
    $pods = Get-Content "$root\k8s\aks-workload.yaml" -Raw
    if ($pods -notmatch '(?s)podAntiAffinity:\s+requiredDuringSchedulingIgnoredDuringExecution:\s+- labelSelector:\s+matchLabels:\s+app: csl-api\s+topologyKey: kubernetes.io/hostname' -or
        $pods -notmatch 'externalTrafficPolicy: Local' -or
        $pods -notmatch 'azure-load-balancer-health-probe-interval: "5"' -or
        $pods -notmatch 'azure-load-balancer-health-probe-num-of-probe: "2"' -or
        $pods -notmatch '(?s)name: Kestrel__EndpointDefaults__Protocols\s+value: Http1' -or
        $pods -notmatch '(?s)name: Orders__CacheImmutableReads\s+value: "true"' -or
        $pods -notmatch '(?s)name: Orders__SharedCacheHost\s+value: "__SHARED_CACHE_HOST__"') {
        throw 'Distinct workers, node-local probes, HTTP/1.1 and confirmed immutable-read caching are required.'
    }
    foreach ($type in @('Microsoft.KeyVault/vaults','Microsoft.ContainerRegistry/registries','Microsoft.DBforPostgreSQL/flexibleServers')) {
        $resource = @($w.resources | Where-Object type -EQ $type)[0]
        $access = if ($type -like '*flexibleServers') { $resource.properties.network.publicNetworkAccess } else { $resource.properties.publicNetworkAccess }
        if ($access -ne 'Disabled') { throw "Public data-plane access is enabled: $type" }
    }
    $native = Get-Content "$root\infra\aks-native-scenarios.bicep" -Raw
    if ($native -notmatch 'virtualmachinescaleset:shutdown' -or $native -match 'InstanceIds|Random|automationAccounts' -or
        $native -notmatch "GracefulShutdown', value: 'false'") { throw 'Native deterministic VMSS fault contract failed.' }
    foreach ($file in Get-ChildItem "$root\scripts" -Filter '*Aks*.ps1' -Recurse) {
        $tokens=$null; $errors=$null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors) | Out-Null
        if ($errors) { $errors | Out-String | Write-Output; throw 'AKS script parse failed.' }
    }
    Write-Output 'AKS Bicep compilation, private endpoints/identity, fixed zonal pools and native shutdown contracts passed.'
} finally { Remove-Item -LiteralPath $tmp -Recurse -Force }
