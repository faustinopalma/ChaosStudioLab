targetScope = 'subscription'

@secure()
param postgresqlAdministratorPassword string
param runnerSshPublicKey string
param deploymentInstanceId string
param prerequisitePrincipalIds object
param sourceRevision string
param location string = 'spaincentral'
param resourceGroupLocation string = location
param chaosWorkspaceLocation string = 'swedencentral'
param operationsLocation string = 'swedencentral'
param networkResourceGroupName string
param workloadResourceGroupName string
param operationsResourceGroupName string

var groupNames = [
  networkResourceGroupName
  workloadResourceGroupName
  operationsResourceGroupName
]

resource groups 'Microsoft.Resources/resourceGroups@2024-03-01' = [for name in groupNames: {
  name: name
  location: resourceGroupLocation
  tags: {
    project: 'ChaosStudioLab'
    labId: 'lab-dev01'
    deploymentInstanceId: deploymentInstanceId
    environment: 'nonproduction'
    owner: 'lab-operator'
  }
}]

module infrastructure 'main.bicep' = {
  name: 'csl-infrastructure'
  scope: groups[0]
  params: {
    location: location
    chaosWorkspaceLocation: chaosWorkspaceLocation
    operationsLocation: operationsLocation
    labSubscriptionId: subscription().subscriptionId
    networkResourceGroupName: networkResourceGroupName
    workloadResourceGroupName: workloadResourceGroupName
    operationsResourceGroupName: operationsResourceGroupName
    postgresqlAdministratorPassword: postgresqlAdministratorPassword
    runnerSshPublicKey: runnerSshPublicKey
    deploymentInstanceId: deploymentInstanceId
    prerequisitePrincipalIds: prerequisitePrincipalIds
    sourceRevision: sourceRevision
  }
  dependsOn: [
    groups
  ]
}
