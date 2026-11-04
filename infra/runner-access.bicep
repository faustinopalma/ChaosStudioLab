targetScope = 'resourceGroup'

param runnerPrincipalId string
param registryName string
param vaultName string
param logAnalyticsName string

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: vaultName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: logAnalyticsName
}

resource push 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, runnerPrincipalId, '8311e382-0749-4cb8-b61a-304f252e45ec')
  scope: registry
  properties: {
    principalId: runnerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
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
