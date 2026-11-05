targetScope = 'resourceGroup'

@description('Validated deployment location; subscription-level PostgreSQL zone-redundant HA eligibility is required.')
param location string = 'spaincentral'

param chaosWorkspaceLocation string = 'swedencentral'

param operationsLocation string = 'swedencentral'

@description('Approved subscription containing the three lab resource groups.')
param labSubscriptionId string = subscription().subscriptionId

@description('Unique identifier included in resource tags for this deployment instance.')
@minLength(1)
@maxLength(64)
param deploymentInstanceId string

@description('Live principal IDs of the manifest-owned prerequisite identities, resolved before ARM what-if.')
param prerequisitePrincipalIds object
param sourceRevision string

@description('Exact lab-owned networking resource group. This template must be deployed to it.')
param networkResourceGroupName string

@description('Exact lab-owned workload resource group.')
param workloadResourceGroupName string

@description('Exact lab-owned operations resource group.')
param operationsResourceGroupName string

@secure()
@description('Bootstrap administrator password required by the PostgreSQL create API. Password authentication is disabled on the server.')
param postgresqlAdministratorPassword string

@description('SSH public key installed on the single private runner.')
param runnerSshPublicKey string

@description('Bastion subnet within the operations VNet.')
param operationsBastionSubnetPrefix string = '10.82.2.0/26'

@description('Workload VNet address range from config/lab.json.')
param workloadAddressPrefix string = '10.81.0.0/16'

@description('Operations VNet address range from config/lab.json.')
param operationsAddressPrefix string = '10.82.0.0/16'

@description('Dedicated App Service regional VNet Integration subnet.')
param appServiceIntegrationSubnetPrefix string = '10.81.0.0/24'

@description('Workload private-endpoint subnet.')
param workloadPrivateEndpointsSubnetPrefix string = '10.81.10.0/24'

@description('Operations management subnet.')
param operationsSubnetPrefix string = '10.82.1.0/24'

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
var privateDnsZoneIds = [for name in privateDnsZoneNames: resourceId(labSubscriptionId, networkResourceGroupName, 'Microsoft.Network/privateDnsZones', name)]
var operationsPublicIpNames = ['pip-csl-operations-egress', 'pip-csl-operations-bastion']
var workloadVnetId = resourceId(labSubscriptionId, workloadResourceGroupName, 'Microsoft.Network/virtualNetworks', 'vnet-csl-workload')
var operationsVnetId = resourceId(labSubscriptionId, operationsResourceGroupName, 'Microsoft.Network/virtualNetworks', 'vnet-csl-operations')
var workloadResourceGroupId = '/subscriptions/${labSubscriptionId}/resourceGroups/${workloadResourceGroupName}'
var workloadSuffix = uniqueString(workloadResourceGroupId, deploymentInstanceId)
var resourceNames = {
  application: 'csl-api-${workloadSuffix}'
  vault: take('csl-kv-${workloadSuffix}', 24)
  postgres: take('csl-pg-${workloadSuffix}', 63)
  logs: 'law-csl-${workloadSuffix}'
  insights: 'appi-csl-${workloadSuffix}'
  monitorScope: 'ampls-csl-${workloadSuffix}'
  chaosWorkspace: 'csl-chaos-${workloadSuffix}'
}

module networkDeployment 'modules/network-core.bicep' = {
  name: 'csl-network-core'
  scope: resourceGroup(labSubscriptionId, networkResourceGroupName)
  params: {
    location: operationsLocation
    deploymentInstanceId: deploymentInstanceId
    privateDnsZoneNames: privateDnsZoneNames
    publicIpNames: operationsPublicIpNames
  }
}

module workloadDeployment 'modules/workload.bicep' = {
  name: 'csl-workload'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    location: location
    chaosWorkspaceLocation: chaosWorkspaceLocation
    resourceNames: resourceNames
    deploymentInstanceId: deploymentInstanceId
    privateDnsZoneIds: privateDnsZoneIds
    workloadAddressPrefix: workloadAddressPrefix
    appServiceIntegrationSubnetPrefix: appServiceIntegrationSubnetPrefix
    privateEndpointsSubnetPrefix: workloadPrivateEndpointsSubnetPrefix
    postgresqlAdministratorPassword: postgresqlAdministratorPassword
    migrationPrincipalId: prerequisitePrincipalIds.migration
  }
  dependsOn: [networkDeployment]
}

module operationsDeployment 'modules/operations.bicep' = {
  name: 'csl-operations'
  scope: resourceGroup(labSubscriptionId, operationsResourceGroupName)
  params: {
    location: location
    operationsLocation: operationsLocation
    deploymentInstanceId: deploymentInstanceId
    operationsAddressPrefix: operationsAddressPrefix
    operationsSubnetPrefix: operationsSubnetPrefix
    bastionSubnetPrefix: operationsBastionSubnetPrefix
    natPublicIpId: resourceId(labSubscriptionId, networkResourceGroupName, 'Microsoft.Network/publicIPAddresses', operationsPublicIpNames[0])
    bastionPublicIpId: resourceId(labSubscriptionId, networkResourceGroupName, 'Microsoft.Network/publicIPAddresses', operationsPublicIpNames[1])
    migrationIdentityId: resourceId(labSubscriptionId, workloadResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'id-csl-migrations')
    runnerSshPublicKey: runnerSshPublicKey
  }
  dependsOn: [networkDeployment]
}

module dnsLinks 'modules/dns-links.bicep' = {
  name: 'csl-private-dns-links'
  scope: resourceGroup(labSubscriptionId, networkResourceGroupName)
  params: {
    deploymentInstanceId: deploymentInstanceId
    workloadVnetId: workloadVnetId
    operationsVnetId: operationsVnetId
  }
  dependsOn: [networkDeployment, workloadDeployment, operationsDeployment]
}

module workloadToOperations 'modules/vnet-peering.bicep' = {
  name: 'csl-peer-workload-to-operations'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    sourceVnetName: 'vnet-csl-workload'
    remoteVnetId: operationsVnetId
    peeringName: 'workload-to-operations'
  }
  dependsOn: [workloadDeployment, operationsDeployment]
}

module operationsToWorkload 'modules/vnet-peering.bicep' = {
  name: 'csl-peer-operations-to-workload'
  scope: resourceGroup(labSubscriptionId, operationsResourceGroupName)
  params: {
    sourceVnetName: 'vnet-csl-operations'
    remoteVnetId: workloadVnetId
    peeringName: 'operations-to-workload'
  }
  dependsOn: [workloadDeployment, operationsDeployment]
}

module runnerWorkloadAccess 'runner-access.bicep' = {
  name: 'csl-runner-workload-access'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    runnerPrincipalId: prerequisitePrincipalIds.runner
    applicationName: resourceNames.application
    vaultName: resourceNames.vault
    logAnalyticsName: resourceNames.logs
  }
  dependsOn: [workloadDeployment, application]
}

module application 'workload-app.bicep' = {
  name: 'csl-application'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    resourceNames: resourceNames
    vnetId: workloadVnetId
    applicationPrivateDnsZoneId: privateDnsZoneIds[0]
    sourceRevision: sourceRevision
  }
  dependsOn: [networkDeployment, workloadDeployment]
}

output network object = {
  privateDnsZoneIds: networkDeployment.outputs.privateDnsZoneIds
}

output workload object = {
  vnetId: workloadDeployment.outputs.vnetId
  vnetName: workloadDeployment.outputs.vnetName
  postgresId: workloadDeployment.outputs.postgresId
  keyVaultId: workloadDeployment.outputs.keyVaultId
  postgresName: workloadDeployment.outputs.postgresName
  postgresHost: workloadDeployment.outputs.postgresHost
  vaultName: workloadDeployment.outputs.vaultName
  runtimeIdentityId: workloadDeployment.outputs.runtimeIdentityId
  runtimeClientId: workloadDeployment.outputs.runtimeClientId
  runtimePrincipalId: workloadDeployment.outputs.runtimePrincipalId
  migrationIdentityId: workloadDeployment.outputs.migrationIdentityId
  migrationClientId: workloadDeployment.outputs.migrationClientId
  chaosWorkspaceName: workloadDeployment.outputs.chaosWorkspaceName
  chaosScenarioId: workloadDeployment.outputs.chaosScenarioId
  chaosConfigurationId: workloadDeployment.outputs.chaosConfigurationId
  logAnalyticsId: workloadDeployment.outputs.logAnalyticsId
  logAnalyticsCustomerId: workloadDeployment.outputs.logAnalyticsCustomerId
  applicationId: application.outputs.applicationId
  applicationName: application.outputs.applicationName
  applicationFqdn: application.outputs.applicationFqdn
  scmFqdn: application.outputs.scmFqdn
}

output operations object = {
  bastionName: operationsDeployment.outputs.bastionName
  bastionId: operationsDeployment.outputs.bastionId
  outboundNatId: operationsDeployment.outputs.outboundNatId
  vnetId: operationsDeployment.outputs.vnetId
  vnetName: operationsDeployment.outputs.vnetName
  runnerId: operationsDeployment.outputs.runnerId
  runnerName: operationsDeployment.outputs.runnerName
  runnerIdentityId: operationsDeployment.outputs.runnerIdentityId
  runnerClientId: operationsDeployment.outputs.runnerClientId
  runnerPrincipalId: operationsDeployment.outputs.runnerPrincipalId
}
