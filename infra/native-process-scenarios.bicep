targetScope = 'resourceGroup'

param workspaceName string
param applicationResourceId string
@minLength(1)
param instanceId string
@allowed([
  '1'
  '2'
  '3'
])
param logicalZone string
@description('Both platforms name the dotnet application process. On Windows the out-of-process host runs the application as dotnet, separate from the main and SCM w3wp workers that share one process name.')
@allowed([
  'linux'
  'windows'
])
param platform string = 'linux'

var processNameParameters = [
  {
    key: 'ProcessName'
    value: 'dotnet'
  }
]

resource workspace 'Microsoft.Chaos/workspaces@2026-08-01-preview' existing = {
  name: workspaceName
}

var selections = [
  {
    name: '${platform}-exact-instance-process-crash'
    instanceIds: [instanceId]
    zones: []
  }
  {
    name: '${platform}-verified-zone-process-crash'
    instanceIds: []
    zones: [logicalZone]
  }
]

resource scenarios 'Microsoft.Chaos/workspaces/scenarios@2026-08-01-preview' = [for selection in selections: {
  parent: workspace
  name: selection.name
  properties: {
    description: 'Operator-selected native discrete ${platform} process crash; independent instance/process evidence is required.'
    parameters: []
    actions: [
      {
        name: 'native-main-process-crash'
        actionId: 'urn:csci:microsoft:appservice:killprocess/1.0.0'
        description: 'Kill the main ${platform} worker process using an explicit instance or verified logical-zone selector.'
        duration: 'PT1M'
        parameters: concat(processNameParameters, [
          {
            key: 'InstanceIds'
            value: string(selection.instanceIds)
          }
          {
            key: 'Zones'
            value: string(selection.zones)
          }
        ])
      }
    ]
  }
}]

resource configurations 'Microsoft.Chaos/workspaces/scenarios/configurations@2026-08-01-preview' = [for (selection, index) in selections: {
  parent: scenarios[index]
  name: 'exact-owned-application'
  properties: {
    scenarioId: scenarios[index].id
    parameters: []
    resourceTargeting: {
      include: {
        resources: [applicationResourceId]
      }
    }
  }
}]

output instanceConfigurationId string = configurations[0].id
output zoneConfigurationId string = configurations[1].id
output selectedInstanceId string = instanceId
output selectedLogicalZone string = logicalZone
output platform string = platform
