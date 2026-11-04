targetScope = 'resourceGroup'

@description('Deployment identifier used on extension resources.')
param deploymentInstanceId string

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' existing = {
  name: 'aa-csl-control'
}

resource workerGroup 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups@2024-10-23' existing = {
  parent: automationAccount
  name: 'hrg-csl-control'
}

resource worker1 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: 'vm-csl-worker-1'
}

resource worker2 'Microsoft.Compute/virtualMachines@2024-07-01' existing = {
  name: 'vm-csl-worker-2'
}

resource worker1Extension 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: worker1
  name: 'HybridWorkerExtension'
  location: resourceGroup().location
  tags: labTags
  properties: {
    publisher: 'Microsoft.Azure.Automation.HybridWorker'
    type: 'HybridWorkerForLinux'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    forceUpdateTag: deploymentInstanceId
    settings: {
      AutomationAccountURL: automationAccount.properties.automationHybridServiceUrl
    }
  }
  dependsOn: [
    worker1Membership
  ]
}

resource worker2Extension 'Microsoft.Compute/virtualMachines/extensions@2024-11-01' = {
  parent: worker2
  name: 'HybridWorkerExtension'
  location: resourceGroup().location
  tags: labTags
  properties: {
    publisher: 'Microsoft.Azure.Automation.HybridWorker'
    type: 'HybridWorkerForLinux'
    typeHandlerVersion: '1.1'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
    forceUpdateTag: deploymentInstanceId
    settings: {
      AutomationAccountURL: automationAccount.properties.automationHybridServiceUrl
    }
  }
  dependsOn: [
    worker2Membership
  ]
}

resource worker1Membership 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups/hybridRunbookWorkers@2024-10-23' = {
  parent: workerGroup
  name: guid(workerGroup.id, worker1.id)
  properties: {
    vmResourceId: worker1.id
  }
}

resource worker2Membership 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups/hybridRunbookWorkers@2024-10-23' = {
  parent: workerGroup
  name: guid(workerGroup.id, worker2.id)
  properties: {
    vmResourceId: worker2.id
  }
}

output workerIds array = [
  worker1.id
  worker2.id
]
