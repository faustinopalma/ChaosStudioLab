targetScope = 'subscription'

@secure()
param postgresqlAdministratorPassword string
param runnerSshPublicKey string
param deploymentInstanceId string
param prerequisitePrincipalIds object
param location string = 'swedencentral'
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
  location: location
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
    labSubscriptionId: subscription().subscriptionId
    networkResourceGroupName: networkResourceGroupName
    workloadResourceGroupName: workloadResourceGroupName
    operationsResourceGroupName: operationsResourceGroupName
    postgresqlAdministratorPassword: postgresqlAdministratorPassword
    runnerSshPublicKey: runnerSshPublicKey
    deploymentInstanceId: deploymentInstanceId
    prerequisitePrincipalIds: prerequisitePrincipalIds
  }
  dependsOn: [
    groups
  ]
}
