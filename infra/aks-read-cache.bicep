param location string = 'swedencentral'
param deploymentInstanceId string
param workloadResourceGroupName string
param workloadVnetId string
param operationsVnetId string
param runtimePrincipalId string
@description('Label used for DNS link and nested deployment names; aks or aca.')
param labelPrefix string = 'aks'

var tags = { project: 'ChaosStudioLab', labId: 'lab-dev01', deploymentInstanceId: deploymentInstanceId }
resource workloadGroup 'Microsoft.Resources/resourceGroups@2024-03-01' existing = {
  name: workloadResourceGroupName
  scope: subscription()
}
resource dns 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.redis.azure.net'
  location: 'global'
  tags: tags
}
resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (id, index) in [workloadVnetId, operationsVnetId]: {
  parent: dns
  name: index == 0 ? '${labelPrefix}-workload' : '${labelPrefix}-operations'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: id } }
}]
module cache 'br/public:avm/res/cache/redis-enterprise:0.5.1' = {
  name: 'csl-${labelPrefix}-shared-cache'
  scope: workloadGroup
  params: {
    name: 'csl-cache-${uniqueString(workloadGroup.id)}'
    location: location
    tags: tags
    enableTelemetry: false
    skuName: 'Balanced_B5'
    highAvailability: 'Enabled'
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Disabled'
    database: {
      name: 'default'
      port: 10000
      clientProtocol: 'Encrypted'
      clusteringPolicy: 'OSSCluster'
      evictionPolicy: 'AllKeysLRU'
      accessKeysAuthentication: 'Disabled'
      persistence: { type: 'disabled' }
      accessPolicyAssignments: [{ name: 'runtime', userObjectId: runtimePrincipalId, accessPolicyName: 'default' }]
    }
    privateEndpoints: [{
      name: 'pe-csl-read-cache'
      subnetResourceId: '${workloadVnetId}/subnets/private-endpoints'
      privateDnsZoneGroup: {
        privateDnsZoneGroupConfigs: [{ privateDnsZoneResourceId: dns.id }]
      }
    }]
  }
}
output readCache object = { id: cache.outputs.resourceId, name: cache.outputs.name, host: cache.outputs.hostName, port: cache.outputs.port }
