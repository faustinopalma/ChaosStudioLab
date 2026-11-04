$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
function Compile([string] $File) {
    $result = & az bicep build --file (Join-Path $root $File) --stdout
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $File" }
    ($result -join "`n") | ConvertFrom-Json -AsHashtable
}
function Resources([hashtable] $Template) {
    foreach ($r in $Template.resources) {
        $r
        if ($r.type -eq 'Microsoft.Resources/deployments') { Resources $r.properties.template }
    }
}
function Assert([bool] $Condition, [string] $Message) {
    if (-not $Condition) { throw $Message }
}
$template = Compile 'infra\main.bicep'
Assert ($template.parameters.location.allowedValues.Count -eq 3 -and
    'italynorth' -in $template.parameters.location.allowedValues -and
    'swedencentral' -in $template.parameters.location.allowedValues -and
    'spaincentral' -in $template.parameters.location.allowedValues) 'Only the three explicitly selected workload candidates may reach ARM deployment.'
$workloadModule = @($template.resources | Where-Object name -eq 'csl-workload')[0]
Assert ($template.parameters.chaosWorkspaceLocation.defaultValue -eq 'swedencentral' -and
    $workloadModule.properties.parameters.chaosWorkspaceLocation.value -eq "[parameters('chaosWorkspaceLocation')]") 'Workspace placement must be wired independently of the workload region.'
Assert ($template.parameters.operationsLocation.defaultValue -eq 'swedencentral' -and
    @($template.resources | Where-Object name -eq 'csl-network-core')[0].properties.parameters.location.value -eq "[parameters('operationsLocation')]") 'Management public IPs must use the operations region.'
$resources = @(Resources $template)
$retired = @($resources | Where-Object {
    $_.type -match '^Microsoft\.(App|Automation|ContainerRegistry|Storage)/' -or
    $_.name -match 'worker-[12]|id-csl-control|control-contributor'
})
Assert ($retired.Count -eq 0) 'Retired container, registry, Automation, control storage or worker resources remain.'
$app = @($resources | Where-Object type -eq 'Microsoft.Web/sites')
Assert ($app.Count -eq 1) 'Expected exactly one Linux Web App.'
$p = $app[0].properties
Assert ($p.reserved -and $p.publicNetworkAccess -eq 'Disabled' -and $p.httpsOnly -and
    -not $p.clientAffinityEnabled) 'Linux/private/HTTPS/non-affinity app contract drifted.'
Assert ($p.virtualNetworkSubnetId -like '*/subnets/app-service-integration*' -and
    $p.siteConfig.vnetRouteAllEnabled -and $p.siteConfig.linuxFxVersion -eq 'DOTNETCORE|10.0' -and
    $p.siteConfig.healthCheckPath -eq '/health/live') 'Integration, runtime or liveness-based App Service Health Check drifted.'
$settings = @{}
foreach ($setting in $p.siteConfig.appSettings) { $settings[$setting.name] = $setting.value }
Assert ($settings.WEBSITE_RUN_FROM_PACKAGE -eq '1' -and $settings.SCM_DO_BUILD_DURING_DEPLOYMENT -eq 'false') 'Versioned package deployment contract drifted.'
$policies = @($resources | Where-Object type -eq 'Microsoft.Web/sites/basicPublishingCredentialsPolicies')
Assert ($policies.Count -eq 2 -and @($policies | Where-Object { $_.properties.allow }).Count -eq 0) 'SCM/FTP basic credentials must remain disabled.'
$endpoint = @($resources | Where-Object name -eq 'pe-csl-app-service')[0]
Assert ($endpoint.properties.subnet.id -like '*/subnets/private-endpoints*' -and
    $endpoint.properties.privateLinkServiceConnections[0].properties.groupIds[0] -eq 'sites') 'Inbound Private Endpoint must use its own subnet and sites group.'
$network = @($template.resources | Where-Object name -eq 'csl-network-core')[0].properties.template
Assert ('privatelink.azurewebsites.net' -in $template.variables.privateDnsZoneNames -and
    @($template.variables.privateDnsZoneNames | Where-Object { $_ -match 'azurecontainer|azurecr|privatelink\.azure-automation\.net' }).Count -eq 0) 'Application/SCM DNS or retired DNS zones drifted.'
foreach ($module in @($template.resources | Where-Object type -eq 'Microsoft.Resources/deployments')) {
    foreach ($parameter in $module.properties.parameters.Values) {
        Assert ($parameter.value -notlike '*reference(*') 'Nested module parameters must use source-derived names/IDs rather than unresolved deployment-output references.'
    }
}
$vnets = @($resources | Where-Object type -eq 'Microsoft.Network/virtualNetworks')
Assert ($vnets.Count -eq 2) 'Expected exactly two VNets.'
$work = @($vnets | Where-Object name -eq 'vnet-csl-workload')[0]
$integration = @($work.properties.subnets | Where-Object name -eq 'app-service-integration')[0]
Assert ($integration.properties.delegations[0].properties.serviceName -eq 'Microsoft.Web/serverFarms') 'App Service subnet delegation drifted.'
$vms = @($resources | Where-Object type -eq 'Microsoft.Compute/virtualMachines')
Assert ($vms.Count -eq 1 -and $vms[0].name -eq 'vm-csl-runner') 'Exactly one private runner is required.'
Assert ($vms[0].location -eq "[parameters('operationsLocation')]" -and
    @($vnets | Where-Object name -eq 'vnet-csl-operations')[0].location -eq "[parameters('operationsLocation')]" -and
    $work.location -eq "[parameters('location')]") 'Management and workload regions must be independently wired without moving the existing identity.'
$nics = @($resources | Where-Object type -eq 'Microsoft.Network/networkInterfaces')
Assert ($nics.Count -eq 1 -and -not $nics[0].properties.ipConfigurations[0].properties.ContainsKey('publicIPAddress')) 'The runner must have only a private NIC.'
Assert (@($resources | Where-Object type -eq 'Microsoft.Network/bastionHosts').Count -eq 1 -and
    @($resources | Where-Object type -eq 'Microsoft.Network/natGateways').Count -eq 1) 'Retained Bastion/NAT management path drifted.'
$pg = @($resources | Where-Object type -eq 'Microsoft.DBforPostgreSQL/flexibleServers')[0]
Assert ($pg.properties.network.publicNetworkAccess -eq 'Disabled' -and
    $pg.properties.highAvailability.mode -eq 'ZoneRedundant') 'Private PostgreSQL zone-redundant HA drifted.'
Assert (@($resources | Where-Object type -like 'Microsoft.Chaos/targets*').Count -eq 0 -and
    @($resources | Where-Object type -eq 'Microsoft.Chaos/workspaces').Count -eq 1) 'Modern Workspaces must remain the only Chaos model.'
$workspace = @($resources | Where-Object type -eq 'Microsoft.Chaos/workspaces')[0]
Assert ($workspace.location -eq "[parameters('chaosWorkspaceLocation')]") 'Cross-region targeting must not deploy the Workspace to the workload region.'
$operations = @($template.resources | Where-Object name -eq 'csl-operations')[0].properties.template
Assert ($operations.variables.storageRegionNames.spaincentral -eq 'SpainCentral') 'Spain Central Storage egress service-tag mapping is missing.'
$plan = Compile 'infra\modules\app-service-plan.bicep'
$serverFarm = @($plan.resources | Where-Object type -eq 'Microsoft.Web/serverfarms')[0]
Assert ($serverFarm.kind -eq 'linux' -and $serverFarm.properties.reserved -and
    $serverFarm.properties.zoneRedundant -and -not $serverFarm.properties.perSiteScaling -and
    $serverFarm.sku.capacity -eq 6) 'The early plan must retain six fixed zone-redundant Linux workers.'
Assert ($plan.parameters.planSku.allowedValues.Count -eq 6 -and
    'P0v3' -in $plan.parameters.planSku.allowedValues -and 'P2v2' -in $plan.parameters.planSku.allowedValues -and
    $serverFarm.sku.tier -match "endsWith.*'v2'.*'PremiumV2'.*'v4'.*'PremiumV4'.*'PremiumV3'") 'Premium SKU generations must map to their correct tiers.'
$wrapper = Compile 'infra\validation.bicep'
$wrappedDeployment = @($wrapper.resources | Where-Object type -eq 'Microsoft.Resources/deployments')[0]
Assert ($wrappedDeployment.properties.parameters.sourceRevision.value -eq "[parameters('sourceRevision')]" -and
    $wrappedDeployment.properties.parameters.prerequisitePrincipalIds.value -eq "[parameters('prerequisitePrincipalIds')]") 'Validation must use the exact source/principal inputs.'
Assert ($wrapper.resources[0].location -eq "[parameters('resourceGroupLocation')]" -and
    $wrappedDeployment.properties.parameters.chaosWorkspaceLocation.value -eq "[parameters('chaosWorkspaceLocation')]") 'Group metadata location and Workspace location must remain independent of regional workload placement.'
'Private Linux App Service topology, SCM credentials, subnet separation, fixed-six-worker plan, retained HA and single runner contracts passed.'
