targetScope = 'resourceGroup'

param runnerPrincipalId string
param applicationName string
param vaultName string
param logAnalyticsName string

resource app 'Microsoft.Web/sites@2025-03-01' existing = {
  name: applicationName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource publish 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, runnerPrincipalId, 'de139f84-1756-47ae-9be6-808fbbe84772')
  scope: app
  properties: {
    principalId: runnerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')
  }
}

resource secrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, runnerPrincipalId, 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  scope: vault
  properties: {
    principalId: runnerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
  }
}

resource monitorRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(workspace.id, runnerPrincipalId, '73c42c96-874c-492b-b04d-ab87d138a893')
  scope: workspace
  properties: {
    principalId: runnerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
  }
}
