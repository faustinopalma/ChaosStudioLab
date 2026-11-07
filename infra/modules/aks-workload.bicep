param location string
param deploymentInstanceId string
param prerequisitePrincipalIds object
param privateDnsZoneIds object
param nodeNatPublicIpId string
param nodeResourceGroupName string
param kubernetesVersion string
@secure()
param postgresqlAdministratorPassword string

var tags = { project: 'ChaosStudioLab', labId: 'lab-dev01', environment: 'nonproduction', owner: 'lab-operator', deploymentInstanceId: deploymentInstanceId }
var suffix = uniqueString(resourceGroup().id, deploymentInstanceId)
var subnetId = resourceId('Microsoft.Network/virtualNetworks/subnets', 'vnet-csl-aks', 'nodes')
var userPools = [
  { name: 'z1a', zone: '1' }
  { name: 'z1b', zone: '1' }
  { name: 'z2a', zone: '2' }
  { name: 'z2b', zone: '2' }
  { name: 'z3a', zone: '3' }
  { name: 'z3b', zone: '3' }
]
var userPoolProfiles = [for pool in userPools: {
  name: pool.name
  count: 1
  vmSize: 'Standard_D4ds_v5'
  osType: 'Linux'
  osSKU: 'AzureLinux'
  osDiskType: 'Managed'
  osDiskSizeGB: 128
  type: 'VirtualMachineScaleSets'
  mode: 'User'
  availabilityZones: [pool.zone]
  vnetSubnetID: subnetId
  enableAutoScaling: false
  maxPods: 50
  nodeLabels: { workload: 'csl-api' }
  tags: tags
}]
resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-csl-aks'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIpAddresses: [{ id: nodeNatPublicIpId }] }
}
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-csl-aks'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.91.0.0/16'] }
    subnets: [
      { name: 'nodes', properties: { addressPrefix: '10.91.0.0/22', natGateway: { id: nat.id }, defaultOutboundAccess: false } }
      { name: 'private-endpoints', properties: { addressPrefix: '10.91.10.0/24', privateEndpointNetworkPolicies: 'Disabled' } }
    ]
  }
}
resource control 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-aks' }
resource kubelet 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-kubelet' }
resource runtime 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-runtime' }
resource migrations 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-migrations' }
resource chaos 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-chaos' }
resource networkRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vnet.id, control.id, 'network')
  scope: vnet
  properties: { roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7'), principalId: prerequisitePrincipalIds.control, principalType: 'ServicePrincipal' }
}
resource kubeletOperator 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kubelet.id, control.id, 'operator')
  scope: kubelet
  properties: { roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'f1a07417-d97a-45cb-824c-7a7467783830'), principalId: prerequisitePrincipalIds.control, principalType: 'ServicePrincipal' }
}
resource aks 'Microsoft.ContainerService/managedClusters@2025-08-01' = {
  name: 'aks-csl-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Base', tier: 'Standard' }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${control.id}': {} } }
  properties: {
    dnsPrefix: 'csl-${suffix}'
    kubernetesVersion: kubernetesVersion
    nodeResourceGroup: nodeResourceGroupName
    disableLocalAccounts: true
    enableRBAC: true
    aadProfile: { managed: true, enableAzureRBAC: true, tenantID: tenant().tenantId }
    apiServerAccessProfile: { enablePrivateCluster: true, enablePrivateClusterPublicFQDN: false, privateDNSZone: 'system' }
    oidcIssuerProfile: { enabled: true }
    securityProfile: { workloadIdentity: { enabled: true } }
    identityProfile: { kubeletidentity: { resourceId: kubelet.id, clientId: prerequisitePrincipalIds.kubeletClient, objectId: prerequisitePrincipalIds.kubelet } }
    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkDataplane: 'cilium'
      outboundType: 'userAssignedNATGateway'
      loadBalancerSku: 'standard'
      podCidr: '10.92.0.0/16'
      serviceCidr: '10.93.0.0/16'
      dnsServiceIP: '10.93.0.10'
    }
    agentPoolProfiles: concat([
      {
        name: 'system'
        count: 3
        vmSize: 'Standard_D4ds_v5'
        osType: 'Linux'
        osSKU: 'AzureLinux'
        osDiskType: 'Managed'
        osDiskSizeGB: 128
        type: 'VirtualMachineScaleSets'
        mode: 'System'
        availabilityZones: ['1', '2', '3']
        vnetSubnetID: subnetId
        enableAutoScaling: false
        maxPods: 50
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
        tags: tags
      }
    ], userPoolProfiles)
  }
  dependsOn: [networkRole, kubeletOperator]
}
resource federation 'Microsoft.ManagedIdentity/userAssignedIdentities/federatedIdentityCredentials@2023-01-31' = {
  parent: runtime
  name: 'aks-csl-api'
  properties: { issuer: aks.properties.oidcIssuerProfile.issuerURL, subject: 'system:serviceaccount:csl:api', audiences: ['api://AzureADTokenExchange'] }
}
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: take('csl-kv-${suffix}', 24)
  location: location
  tags: tags
  properties: {
    tenantId: tenant().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: { bypass: 'None', defaultAction: 'Deny', ipRules: [], virtualNetworkRules: [] }
  }
}
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'csl-pg-${suffix}'
  location: location
  tags: tags
  sku: { name: 'Standard_D4ds_v5', tier: 'GeneralPurpose' }
  properties: {
    version: '16'
    administratorLogin: 'cslbootstrap'
    administratorLoginPassword: postgresqlAdministratorPassword
    availabilityZone: '1'
    authConfig: { activeDirectoryAuth: 'Enabled', passwordAuth: 'Disabled', tenantId: tenant().tenantId }
    highAvailability: { mode: 'ZoneRedundant', standbyAvailabilityZone: '2' }
    storage: { storageSizeGB: 128 }
    network: { publicNetworkAccess: 'Disabled' }
  }
}
module postgresAdmin 'postgres-admin.bicep' = {
  name: 'csl-pg-admin'
  params: { serverName: postgres.name, principalId: prerequisitePrincipalIds.migration, principalName: migrations.name, tenantId: tenant().tenantId }
}
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'cslacr${suffix}'
  location: location
  tags: tags
  sku: { name: 'Premium' }
  properties: { adminUserEnabled: false, publicNetworkAccess: 'Disabled', networkRuleBypassOptions: 'None', dataEndpointEnabled: true }
}
resource pullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, kubelet.id, 'pull')
  scope: registry
  properties: { roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d'), principalId: prerequisitePrincipalIds.kubelet, principalType: 'ServicePrincipal' }
}
var services = [
  { name: 'postgres', id: postgres.id, group: 'postgresqlServer', zone: privateDnsZoneIds.postgres }
  { name: 'vault', id: vault.id, group: 'vault', zone: privateDnsZoneIds.vault }
  { name: 'registry', id: registry.id, group: 'registry', zone: privateDnsZoneIds.registry }
]
resource endpoints 'Microsoft.Network/privateEndpoints@2024-05-01' = [for service in services: {
  name: 'pe-csl-${service.name}'
  location: location
  tags: tags
  properties: {
    subnet: { id: '${vnet.id}/subnets/private-endpoints' }
    privateLinkServiceConnections: [{ name: service.name, properties: { privateLinkServiceId: service.id, groupIds: [service.group] } }]
  }
}]
resource zoneGroups 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = [for (service, i) in services: {
  parent: endpoints[i]
  name: 'default'
  properties: { privateDnsZoneConfigs: [{ name: service.name, properties: { privateDnsZoneId: service.zone } }] }
}]
output workload object = {
  vnetId: vnet.id
  vnetName: vnet.name
  clusterId: aks.id
  clusterName: aks.name
  privateFqdn: aks.properties.privateFQDN
  nodeResourceGroupName: nodeResourceGroupName
  postgresId: postgres.id
  postgresHost: '${postgres.name}.postgres.database.azure.com'
  postgresName: postgres.name
  vaultId: vault.id
  vaultName: vault.name
  registryId: registry.id
  registryName: registry.name
  registryHost: registry.properties.loginServer
  runtimeClientId: runtime.properties.clientId
  runtimePrincipalId: prerequisitePrincipalIds.runtime
  migrationClientId: migrations.properties.clientId
  chaosIdentityId: chaos.id
  chaosPrincipalId: prerequisitePrincipalIds.chaos
  apiFqdn: 'api.csl.internal'
}
