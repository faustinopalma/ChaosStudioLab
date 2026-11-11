param location string = 'swedencentral'
param deploymentInstanceId string
param networkResourceGroupName string
param workloadResourceGroupName string
param operationsResourceGroupName string
param infrastructureResourceGroupName string
param prerequisitePrincipalIds object
param runnerSshPublicKey string
@secure()
param postgresqlAdministratorPassword string

var zones = ['privatelink.postgres.database.azure.com', 'privatelink.vaultcore.azure.net', 'privatelink.azurecr.io']
var zoneIds = [for name in zones: resourceId(subscription().subscriptionId, networkResourceGroupName, 'Microsoft.Network/privateDnsZones', name)]
var publicIp = 'Microsoft.Network/publicIPAddresses'
var workloadVnetId = resourceId(subscription().subscriptionId, workloadResourceGroupName, 'Microsoft.Network/virtualNetworks', 'vnet-csl-aca')
var operationsVnetId = resourceId(subscription().subscriptionId, operationsResourceGroupName, 'Microsoft.Network/virtualNetworks', 'vnet-csl-operations')
module network 'modules/network-core.bicep' = {
  name: 'csl-aca-network'
  scope: resourceGroup(networkResourceGroupName)
  params: { location: location, deploymentInstanceId: deploymentInstanceId, privateDnsZoneNames: zones, publicIpNames: ['pip-csl-operations-egress', 'pip-csl-operations-bastion', 'pip-csl-aca-egress'] }
}
module workload 'modules/aca-workload.bicep' = {
  name: 'csl-aca-workload'
  scope: resourceGroup(workloadResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    prerequisitePrincipalIds: prerequisitePrincipalIds
    privateDnsZoneIds: { postgres: zoneIds[0], vault: zoneIds[1], registry: zoneIds[2] }
    natPublicIpId: resourceId(subscription().subscriptionId, networkResourceGroupName, publicIp, 'pip-csl-aca-egress')
    infrastructureResourceGroupName: infrastructureResourceGroupName
    postgresqlAdministratorPassword: postgresqlAdministratorPassword
  }
  dependsOn: [network]
}
module operations 'modules/operations.bicep' = {
  name: 'csl-aca-operations'
  scope: resourceGroup(operationsResourceGroupName)
  params: {
    location: location
    operationsLocation: location
    deploymentInstanceId: deploymentInstanceId
    operationsAddressPrefix: '10.97.0.0/16'
    operationsSubnetPrefix: '10.97.1.0/24'
    bastionSubnetPrefix: '10.97.2.0/26'
    natPublicIpId: resourceId(subscription().subscriptionId, networkResourceGroupName, publicIp, 'pip-csl-operations-egress')
    bastionPublicIpId: resourceId(subscription().subscriptionId, networkResourceGroupName, publicIp, 'pip-csl-operations-bastion')
    migrationIdentityId: resourceId(subscription().subscriptionId, workloadResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'id-csl-migrations')
    runnerSshPublicKey: runnerSshPublicKey
  }
  dependsOn: [network]
}
module peerWork 'modules/vnet-peering.bicep' = {
  name: 'csl-aca-peer-work'
  scope: resourceGroup(workloadResourceGroupName)
  params: { sourceVnetName: 'vnet-csl-aca', remoteVnetId: operationsVnetId, peeringName: 'workload-to-operations' }
  dependsOn: [workload, operations]
}
module peerOps 'modules/vnet-peering.bicep' = {
  name: 'csl-aca-peer-ops'
  scope: resourceGroup(operationsResourceGroupName)
  params: { sourceVnetName: 'vnet-csl-operations', remoteVnetId: workloadVnetId, peeringName: 'operations-to-workload' }
  dependsOn: [workload, operations]
}
resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' existing = [for name in zones: { name: name }]
resource linksWork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (name, i) in zones: {
  parent: dnsZones[i]
  name: 'aca-workload'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: workloadVnetId } }
  dependsOn: [network, workload]
}]
resource linksOps 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (name, i) in zones: {
  parent: dnsZones[i]
  name: 'aca-operations'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: operationsVnetId } }
  dependsOn: [network, operations]
}]
module readCache 'aks-read-cache.bicep' = {
  name: 'csl-aca-read-cache'
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    workloadResourceGroupName: workloadResourceGroupName
    workloadVnetId: workloadVnetId
    operationsVnetId: operationsVnetId
    runtimePrincipalId: prerequisitePrincipalIds.runtime
    labelPrefix: 'aca'
  }
  dependsOn: [workload, operations]
}
output workload object = workload.outputs.workload
output readCache object = readCache.outputs.readCache
output operations object = {
  vnetId: operations.outputs.vnetId
  bastionId: operations.outputs.bastionId
  bastionName: operations.outputs.bastionName
  runnerId: operations.outputs.runnerId
  runnerIdentityId: operations.outputs.runnerIdentityId
  runnerClientId: operations.outputs.runnerClientId
  runnerPrincipalId: operations.outputs.runnerPrincipalId
}
