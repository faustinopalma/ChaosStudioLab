param runnerPrincipalId string
param chaosPrincipalId string
param clusterName string
param registryName string
param vaultName string
param postgresName string
resource cluster 'Microsoft.ContainerService/managedClusters@2025-08-01' existing = { name: clusterName }
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = { name: registryName }
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = { name: vaultName }
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = { name: postgresName }
var readers = [runnerPrincipalId, chaosPrincipalId]
resource readerRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principal in readers: {
  name: guid(resourceGroup().id, principal, 'reader')
  properties: { principalId: principal, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7') }
}]
resource push 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, runnerPrincipalId, 'push')
  scope: registry
  properties: { principalId: runnerPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec') }
}
resource secrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, runnerPrincipalId, 'secrets')
  scope: vault
  properties: { principalId: runnerPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') }
}
resource clusterUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cluster.id, runnerPrincipalId, 'clusteruser')
  scope: cluster
  properties: { principalId: runnerPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4abbcc35-e782-43d8-92c5-2d3f1bd2253f') }
}
resource clusterAdmin 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cluster.id, runnerPrincipalId, 'rbacadmin')
  scope: cluster
  properties: { principalId: runnerPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b1ff04bb-8a4e-4dc4-8eb5-8693973ce19b') }
}
resource databaseAction 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(postgres.id, chaosPrincipalId, 'postgres')
  scope: postgres
  properties: { principalId: chaosPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') }
}
