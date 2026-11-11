param location string
param deploymentInstanceId string
param prerequisitePrincipalIds object
param privateDnsZoneIds object
param natPublicIpId string
param infrastructureResourceGroupName string
@secure()
param postgresqlAdministratorPassword string

var tags = { project: 'ChaosStudioLab', labId: 'lab-dev01', environment: 'nonproduction', owner: 'lab-operator', deploymentInstanceId: deploymentInstanceId }
var suffix = uniqueString(resourceGroup().id, deploymentInstanceId)
resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-csl-aca'
  location: location
  tags: tags
  sku: { name: 'Standard' }
  properties: { publicIpAddresses: [{ id: natPublicIpId }] }
}
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-csl-aca'
  location: location
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.96.0.0/16'] }
    subnets: [
      {
        name: 'container-apps'
        properties: {
          addressPrefix: '10.96.0.0/23'
          natGateway: { id: nat.id }
          delegations: [{ name: 'container-apps', properties: { serviceName: 'Microsoft.App/environments' } }]
        }
      }
      { name: 'private-endpoints', properties: { addressPrefix: '10.96.10.0/24', privateEndpointNetworkPolicies: 'Disabled' } }
    ]
  }
}
resource runtime 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-runtime' }
resource migrations 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-migrations' }
resource chaos 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = { name: 'id-csl-chaos' }
resource environment 'Microsoft.App/managedEnvironments@2026-07-01' = {
  name: 'cae-csl-aca'
  location: location
  tags: tags
  properties: {
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
    zoneRedundant: true
    publicNetworkAccess: 'Disabled'
    infrastructureResourceGroup: infrastructureResourceGroupName
    vnetConfiguration: { infrastructureSubnetId: '${vnet.id}/subnets/container-apps', internal: true }
  }
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
  name: guid(registry.id, runtime.id, 'pull')
  scope: registry
  properties: { roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d'), principalId: prerequisitePrincipalIds.runtime, principalType: 'ServicePrincipal' }
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
  environmentId: environment.id
  environmentName: environment.name
  defaultDomain: environment.properties.defaultDomain
  staticIp: environment.properties.staticIp
  infrastructureResourceGroupName: infrastructureResourceGroupName
  postgresId: postgres.id
  postgresHost: '${postgres.name}.postgres.database.azure.com'
  postgresName: postgres.name
  vaultId: vault.id
  vaultName: vault.name
  registryId: registry.id
  registryName: registry.name
  registryHost: registry.properties.loginServer
  runtimeIdentityId: runtime.id
  runtimeClientId: runtime.properties.clientId
  runtimePrincipalId: prerequisitePrincipalIds.runtime
  migrationClientId: migrations.properties.clientId
  chaosIdentityId: chaos.id
  chaosPrincipalId: prerequisitePrincipalIds.chaos
  appName: 'ca-csl-api'
  apiFqdn: 'ca-csl-api.${environment.properties.defaultDomain}'
}
