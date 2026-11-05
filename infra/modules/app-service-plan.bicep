targetScope = 'resourceGroup'

param location string
param deploymentInstanceId string
@allowed([
  'P0v3'
  'P1v2'
  'P1v3'
  'P1v4'
  'P2v2'
  'P2v3'
])
param planSku string = 'P1v3'

resource plan 'Microsoft.Web/serverfarms@2025-03-01' = {
  name: 'asp-csl-linux-baseline'
  location: location
  kind: 'linux'
  tags: {
    project: 'ChaosStudioLab'
    labId: 'lab-dev01'
    environment: 'nonproduction'
    owner: 'lab-operator'
    deploymentInstanceId: deploymentInstanceId
  }
  sku: {
    name: planSku
    tier: endsWith(toLower(planSku), 'v2') ? 'PremiumV2' : (endsWith(toLower(planSku), 'v4') ? 'PremiumV4' : 'PremiumV3')
    capacity: 6
  }
  properties: {
    reserved: true
    zoneRedundant: true
    perSiteScaling: false
  }
}

output planId string = plan.id
