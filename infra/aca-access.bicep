param runnerPrincipalId string
param chaosPrincipalId string
param registryName string
param vaultName string
param postgresName string
resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = { name: registryName }
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = { name: vaultName }
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = { name: postgresName }
var role = {
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  acrPush: '8311e382-0749-4cb8-b61a-304f252e45ec'
  secretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
  contributor: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
}
resource readerRoles 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for principal in [runnerPrincipalId, chaosPrincipalId]: {
  name: guid(resourceGroup().id, principal, 'reader')
  properties: { principalId: principal, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.reader) }
}]
resource push 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, runnerPrincipalId, 'push')
  scope: registry
  properties: { principalId: runnerPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.acrPush) }
}
resource secrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, runnerPrincipalId, 'secrets')
  scope: vault
  properties: { principalId: runnerPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.secretsOfficer) }
}
resource databaseAction 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(postgres.id, chaosPrincipalId, 'postgres')
  scope: postgres
  properties: { principalId: chaosPrincipalId, principalType: 'ServicePrincipal', roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', role.contributor) }
}
