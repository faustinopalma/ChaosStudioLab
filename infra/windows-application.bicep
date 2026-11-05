targetScope = 'resourceGroup'

// Windows comparison target. Linux App Service rejects native process termination
// (DELETE .../instances/{id}/processes/{pid} returns HTTP 400 on every Linux stack),
// so the native App Service process-crash tests run against this private Windows app.
// It reuses the deployed private database, Key Vault, identities, monitoring and Workspace.

param location string
param deploymentInstanceId string
param applicationName string
param resourceNames object
param vnetName string = 'vnet-csl-workload'
param integrationSubnetName string = 'app-service-integration-windows'
param integrationSubnetPrefix string = '10.81.1.0/24'
@description('Existing NSG reused for the separate Windows outbound integration subnet.')
param integrationNsgName string
param applicationPrivateDnsZoneId string
param runnerPrincipalId string
param sourceRevision string
@allowed([
  'P0v3'
  'P1v3'
  'P1v4'
  'P2v3'
])
param planSku string = 'P1v3'

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}
var websiteContributor = 'de139f84-1756-47ae-9be6-808fbbe84772'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}
resource integrationNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' existing = {
  name: integrationNsgName
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

resource integrationSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: integrationSubnetName
  properties: {
    addressPrefix: integrationSubnetPrefix
    networkSecurityGroup: { id: integrationNsg.id }
    delegations: [
      {
        name: 'app-service'
        properties: { serviceName: 'Microsoft.Web/serverFarms' }
      }
    ]
  }
}

module plan 'modules/app-service-plan.bicep' = {
  name: 'csl-windows-plan'
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    planSku: planSku
    platform: 'windows'
  }
}

resource app 'Microsoft.Web/sites@2025-03-01' = {
  name: applicationName
  location: location
  kind: 'app'
  tags: labTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: { '${runtime.id}': {} }
  }
  properties: {
    serverFarmId: plan.outputs.planId
    reserved: false
    httpsOnly: true
    publicNetworkAccess: 'Disabled'
    clientAffinityEnabled: false
    virtualNetworkSubnetId: integrationSubnet.id
    keyVaultReferenceIdentity: runtime.id
    siteConfig: {
      netFrameworkVersion: 'v9.0'
      metadata: [
        { name: 'CURRENT_STACK', value: 'dotnet' }
      ]
      use32BitWorkerProcess: false
      alwaysOn: true
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
  name: 'pe-csl-app-service-windows'
  location: location
  tags: labTags
  properties: {
    subnet: { id: '${vnet.id}/subnets/private-endpoints' }
    privateLinkServiceConnections: [{
      name: 'app-service-windows'
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
  name: guid(app.id, chaos.id, websiteContributor)
  scope: app
  properties: {
    principalId: chaos.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributor)
  }
}
resource runnerAppRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(app.id, runnerPrincipalId, websiteContributor)
  scope: app
  properties: {
    principalId: runnerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', websiteContributor)
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
output planId string = plan.outputs.planId
output integrationSubnetId string = integrationSubnet.id
output platform string = 'windows'
