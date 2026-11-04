targetScope = 'resourceGroup'

@description('Validated deployment location; subscription-level PostgreSQL zone-redundant HA eligibility is required.')
@allowed([
  'italynorth'
  'swedencentral'
])
param location string = 'swedencentral'

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

module networkDeployment 'modules/network-core.bicep' = {
  name: 'csl-network-core'
  scope: resourceGroup(labSubscriptionId, networkResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
  }
}

module workloadDeployment 'modules/workload.bicep' = {
  name: 'csl-workload'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    privateDnsZoneIds: networkDeployment.outputs.privateDnsZoneIds
    workloadAddressPrefix: workloadAddressPrefix
    appServiceIntegrationSubnetPrefix: appServiceIntegrationSubnetPrefix
    privateEndpointsSubnetPrefix: workloadPrivateEndpointsSubnetPrefix
    postgresqlAdministratorPassword: postgresqlAdministratorPassword
    migrationPrincipalId: prerequisitePrincipalIds.migration
  }
}

module operationsDeployment 'modules/operations.bicep' = {
  name: 'csl-operations'
  scope: resourceGroup(labSubscriptionId, operationsResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    operationsAddressPrefix: operationsAddressPrefix
    operationsSubnetPrefix: operationsSubnetPrefix
    bastionSubnetPrefix: operationsBastionSubnetPrefix
    natPublicIpId: networkDeployment.outputs.natPublicIpId
    bastionPublicIpId: networkDeployment.outputs.bastionPublicIpId
    migrationIdentityId: resourceId(labSubscriptionId, workloadResourceGroupName, 'Microsoft.ManagedIdentity/userAssignedIdentities', 'id-csl-migrations')
    runnerSshPublicKey: runnerSshPublicKey
  }
}

module dnsLinks 'modules/dns-links.bicep' = {
  name: 'csl-private-dns-links'
  scope: resourceGroup(labSubscriptionId, networkResourceGroupName)
  params: {
    deploymentInstanceId: deploymentInstanceId
    workloadVnetId: workloadDeployment.outputs.vnetId
    operationsVnetId: operationsDeployment.outputs.vnetId
  }
}

module workloadToOperations 'modules/vnet-peering.bicep' = {
  name: 'csl-peer-workload-to-operations'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    sourceVnetName: workloadDeployment.outputs.vnetName
    remoteVnetId: operationsDeployment.outputs.vnetId
    peeringName: 'workload-to-operations'
  }
}

module operationsToWorkload 'modules/vnet-peering.bicep' = {
  name: 'csl-peer-operations-to-workload'
  scope: resourceGroup(labSubscriptionId, operationsResourceGroupName)
  params: {
    sourceVnetName: operationsDeployment.outputs.vnetName
    remoteVnetId: workloadDeployment.outputs.vnetId
    peeringName: 'operations-to-workload'
  }
}

module runnerWorkloadAccess 'runner-access.bicep' = {
  name: 'csl-runner-workload-access'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    runnerPrincipalId: prerequisitePrincipalIds.runner
    applicationName: application.outputs.applicationName
    vaultName: workloadDeployment.outputs.vaultName
    logAnalyticsName: last(split(workloadDeployment.outputs.logAnalyticsId, '/'))
  }
}

module application 'workload-app.bicep' = {
  name: 'csl-application'
  scope: resourceGroup(labSubscriptionId, workloadResourceGroupName)
  params: {
    location: location
    deploymentInstanceId: deploymentInstanceId
    vnetId: workloadDeployment.outputs.vnetId
    applicationPrivateDnsZoneId: networkDeployment.outputs.privateDnsZoneIds[0]
    sourceRevision: sourceRevision
  }
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
