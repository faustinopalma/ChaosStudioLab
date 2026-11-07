$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$tmp = Join-Path ([IO.Path]::GetTempPath()) "csl-aks-test-$([Guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory $tmp | Out-Null
try {
    foreach ($name in @('aks-main','aks-app-dns','aks-native-scenarios','aks-access','aks-node-access','modules\aks-identities','modules\aks-workload')) {
        $file = Join-Path $tmp "$([IO.Path]::GetFileName($name)).json"
        & az bicep build --file "$root\infra\$name.bicep" --outfile $file --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw "AKS Bicep compilation failed: $name" }
    }
    $w = Get-Content "$tmp\aks-workload.json" -Raw | ConvertFrom-Json -AsHashtable
    $main = Get-Content "$tmp\aks-main.json" -Raw | ConvertFrom-Json -AsHashtable
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
        $pods -notmatch '(?s)name: Orders__CacheImmutableReads\s+value: "true"') {
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
