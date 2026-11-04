targetScope = 'resourceGroup'

param location string
param deploymentInstanceId string
param workloadVnetId string
param operationsVnetId string

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  deploymentInstanceId: deploymentInstanceId
}

var zoneNames = [
  'privatelink.${location}.azurecontainerapps.io'
  'privatelink.postgres.database.azure.com'
  'privatelink.azurecr.io'
  'privatelink.vaultcore.azure.net'
  'privatelink.blob.${environment().suffixes.storage}'
  'privatelink.monitor.azure.com'
  'privatelink.oms.opinsights.azure.com'
  'privatelink.ods.opinsights.azure.com'
  'privatelink.agentsvc.azure-automation.net'
  'privatelink.azure-automation.net'
]

resource zones 'Microsoft.Network/privateDnsZones@2024-06-01' existing = [for zoneName in zoneNames: {
  name: zoneName
}]

resource workloadLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in zoneNames: {
  parent: zones[index]
  name: 'workload'
  location: 'global'
  tags: labTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: workloadVnetId
    }
  }
}]

resource operationsLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [for (zoneName, index) in zoneNames: {
  parent: zones[index]
  name: 'operations'
  location: 'global'
  tags: labTags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: operationsVnetId
    }
  }
}]
