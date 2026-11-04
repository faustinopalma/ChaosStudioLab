targetScope = 'resourceGroup'

param location string
param deploymentInstanceId string

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

var privateDnsZoneNames = [
  'privatelink.azurewebsites.net'
  'privatelink.postgres.database.azure.com'
  'privatelink.vaultcore.azure.net'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
]

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [for zoneName in privateDnsZoneNames: {
  name: zoneName
  location: 'global'
  tags: labTags
}]

resource publicIps 'Microsoft.Network/publicIPAddresses@2023-09-01' = [for purpose in ['egress', 'bastion']: {
  name: 'pip-csl-operations-${purpose}'
  location: location
  tags: labTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}]

output privateDnsZoneIds array = [for (zoneName, index) in privateDnsZoneNames: privateDnsZones[index].id]
output natPublicIpId string = publicIps[0].id
output bastionPublicIpId string = publicIps[1].id
