param location string = 'swedencentral'
param deploymentInstanceId string
param networkResourceGroupName string
param workloadResourceGroupName string
param operationsResourceGroupName string
param nodeResourceGroupName string
param prerequisitePrincipalIds object
param runnerSshPublicKey string
param kubernetesVersion string = '1.35.9'
@secure()
param postgresqlAdministratorPassword string

var zones = ['privatelink.postgres.database.azure.com', 'privatelink.vaultcore.azure.net', 'privatelink.azurecr.io', 'csl.internal']
var zoneIds = [for name in zones: resourceId(subscription().subscriptionId, networkResourceGroupName, 'Microsoft.Network/privateDnsZones', name)]
module network 'modules/network-core.bicep' = {
  name: 'csl-aks-network'
  scope: resourceGroup(networkResourceGroupName)
  params: { location: location, deploymentInstanceId: deploymentInstanceId, privateDnsZoneNames: zones, publicIpNames: ['pip-csl-operations-egress', 'pip-csl-operations-bastion', 'pip-csl-aks-egress'] }
}
module workload 'modules/aks-workload.bicep' = {
  name: 'csl-aks-workload'
  scope: resourceGroup(workloadResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    prerequisitePrincipalIds: prerequisitePrincipalIds
    privateDnsZoneIds: { postgres: zoneIds[0], vault: zoneIds[1], registry: zoneIds[2] }
    nodeNatPublicIpId: resourceId(subscription().subscriptionId, networkResourceGroupName, 'Microsoft.Network/publicIPAddresses', 'pip-csl-aks-egress')
    nodeResourceGroupName: nodeResourceGroupName
    kubernetesVersion: kubernetesVersion
    postgresqlAdministratorPassword: postgresqlAdministratorPassword
  }
  dependsOn: [network]
}
module operations 'modules/operations.bicep' = {
  name: 'csl-aks-operations'
  scope: resourceGroup(operationsResourceGroupName)
  params: {
    location: location
    operationsLocation: location
    deploymentInstanceId: deploymentInstanceId
    operationsAddressPrefix: '10.94.0.0/16'
    operationsSubnetPrefix: '10.94.1.0/24'
    bastionSubnetPrefix: '10.94.2.0/26'
    natPublicIpId: resourceId(subscription().subscriptionId, networkResourceGroupName, 'Microsoft.Network/publicIPAddresses', 'pip-csl-operations-egress')
    bastionPublicIpId: resourceId(subscription().subscriptionId, networkResourceGroupName, 'Microsoft.Network/publicIPAddresses', 'pip-csl-operations-bastion')
    migrationIdentityId: resourceId(subscription().subscriptionId, workloadResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'id-csl-migrations')
    runnerSshPublicKey: runnerSshPublicKey
  }
  dependsOn: [network]
}
module peerWork 'modules/vnet-peering.bicep' = {
  name: 'csl-aks-peer-work'
  scope: resourceGroup(workloadResourceGroupName)
  params: { sourceVnetName: 'vnet-csl-aks', remoteVnetId: operations.outputs.vnetId, peeringName: 'workload-to-operations' }
}
module peerOps 'modules/vnet-peering.bicep' = {
  name: 'csl-aks-peer-ops'
  scope: resourceGroup(operationsResourceGroupName)
  params: { sourceVnetName: 'vnet-csl-operations', remoteVnetId: workload.outputs.workload.vnetId, peeringName: 'operations-to-workload' }
}
resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' existing = [for name in zones: { name: name }]
resource linksWork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (name, i) in zones: {
  parent: dnsZones[i]
  name: 'aks-workload'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: workload.outputs.workload.vnetId } }
}]
resource linksOps 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (name, i) in zones: {
  parent: dnsZones[i]
  name: 'aks-operations'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: operations.outputs.vnetId } }
}]
resource apiDns 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: dnsZones[3]
  name: 'api'
  properties: { ttl: 60, aRecords: [{ ipv4Address: '10.91.3.240' }] }
}
output workload object = workload.outputs.workload
output operations object = {
  vnetId: operations.outputs.vnetId
  bastionId: operations.outputs.bastionId
  runnerId: operations.outputs.runnerId
  runnerIdentityId: operations.outputs.runnerIdentityId
  runnerClientId: operations.outputs.runnerClientId
  runnerPrincipalId: operations.outputs.runnerPrincipalId
}
