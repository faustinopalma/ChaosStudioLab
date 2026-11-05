targetScope = 'resourceGroup'

param location string
param deploymentInstanceId string
param resourceNames object
param vnetId string
param applicationPrivateDnsZoneId string
param sourceRevision string

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

resource plan 'Microsoft.Web/serverfarms@2025-03-01' existing = {
  name: 'asp-csl-linux-baseline'
}
resource runtime 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-csl-runtime'
}
resource chaos 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: 'id-csl-chaos'
}
resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: resourceNames.vault
}
resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: resourceNames.postgres
}
resource insights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: resourceNames.insights
}
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: resourceNames.logs
}

resource app 'Microsoft.Web/sites@2025-03-01' = {
  name: resourceNames.application
  location: location
  kind: 'app,linux'
  tags: labTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${runtime.id}': {} }
  }
  properties: {
    serverFarmId: plan.id
    reserved: true
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    clientAffinityEnabled: false
    virtualNetworkSubnetId: '${vnetId}/subnets/app-service-integration'
    keyVaultReferenceIdentity: runtime.id
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|9.0'
      alwaysOn: true
      appCommandLine: 'dotnet Demo.Api.dll'
      healthCheckPath: '/health/live'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
      ftpsState: 'Disabled'
      vnetRouteAllEnabled: true
      appSettings: [
        { name: 'AZURE_CLIENT_ID', value: runtime.properties.clientId }
        { name: 'ConnectionStrings__Postgres', value: 'Host=${postgres.properties.fullyQualifiedDomainName};Database=csl;Username=id-csl-runtime;SSL Mode=VerifyFull' }
        { name: 'Diagnostics__Token', value: '@Microsoft.KeyVault(VaultName=${vault.name};SecretName=diagnostics-token)' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
        { name: 'LAB_SOURCE_REVISION', value: sourceRevision }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
        { name: 'SCM_DO_BUILD_DURING_DEPLOYMENT', value: 'false' }
      ]
    }
  }
}

resource scmBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: app
  name: 'scm'
  properties: { allow: false }
}
resource ftpBasicAuth 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2025-03-01' = {
  parent: app
  name: 'ftp'
  properties: { allow: false }
}
resource endpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-csl-app-service'
  location: location
  tags: labTags
  properties: {
    subnet: { id: '${vnetId}/subnets/private-endpoints' }
    privateLinkServiceConnections: [{
      name: 'app-service'
      properties: {
        privateLinkServiceId: app.id
        groupIds: ['sites']
      }
    }]
  }
}
resource dns 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: endpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [{
      name: 'application-and-scm'
      properties: { privateDnsZoneId: applicationPrivateDnsZoneId }
    }]
  }
}
resource chaosAppRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, chaos.id, 'de139f84-1756-47ae-9be6-808fbbe84772')
  scope: app
  properties: {
    principalId: chaos.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'de139f84-1756-47ae-9be6-808fbbe84772')
  }
}
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'csl-app-service-logs'
  scope: app
  properties: {
    workspaceId: logs.id
    logs: [{ categoryGroup: 'allLogs', enabled: true }]
    metrics: [{ category: 'AllMetrics', enabled: true }]
  }
}

output applicationId string = app.id
output applicationName string = app.name
output applicationFqdn string = app.properties.defaultHostName
output scmFqdn string = filter(app.properties.enabledHostNames, host => contains(host, '.scm.'))[0]
