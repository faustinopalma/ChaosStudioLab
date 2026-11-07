param chaosPrincipalId string
param runnerPrincipalId string
param privateApiZoneName string
param operationsVnetId string

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var vmContributorRoleId = '9980e02c-c2be-4d73-94e8-173b1dc7cf3c'
resource readers 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principal in [chaosPrincipalId, runnerPrincipalId]: {
  name: guid(resourceGroup().id, principal, readerRoleId)
  properties: {
    principalId: principal
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
  }
}]
resource actionRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, chaosPrincipalId, vmContributorRoleId)
  properties: {
    principalId: chaosPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', vmContributorRoleId)
  }
}
resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = { name: privateApiZoneName }
resource runnerLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: zone
  name: 'csl-private-runner'
  location: 'global'
  properties: { virtualNetwork: { id: operationsVnetId }, registrationEnabled: false }
}
