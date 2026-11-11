param defaultDomain string
param staticIp string
param vnetIds array
param deploymentInstanceId string

var tags = { project: 'ChaosStudioLab', labId: 'lab-dev01', deploymentInstanceId: deploymentInstanceId }
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: defaultDomain
  location: 'global'
  tags: tags
}
resource records 'Microsoft.Network/privateDnsZones/A@2024-06-01' = [for name in ['*', '@']: {
  parent: zone
  name: name
  properties: { ttl: 300, aRecords: [{ ipv4Address: staticIp }] }
}]
resource links 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (id, index) in vnetIds: {
  parent: zone
  name: index == 0 ? 'aca-workload' : 'aca-operations'
  location: 'global'
  properties: { registrationEnabled: false, virtualNetwork: { id: id } }
}]
