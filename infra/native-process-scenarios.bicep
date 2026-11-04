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

resource workspace 'Microsoft.Chaos/workspaces@2026-08-01-preview' existing = {
  name: workspaceName
}

var selections = [
  {
    name: 'linux-exact-instance-process-crash'
    instanceIds: [instanceId]
    zones: []
  }
  {
    name: 'linux-verified-zone-process-crash'
    instanceIds: []
    zones: [logicalZone]
  }
]

resource scenarios 'Microsoft.Chaos/workspaces/scenarios@2026-08-01-preview' = [for selection in selections: {
  parent: workspace
  name: selection.name
  properties: {
    description: 'Operator-selected native discrete Linux process crash; independent instance/process evidence is required.'
    parameters: []
    actions: [
      {
        name: 'native-main-process-crash'
        actionId: 'urn:csci:microsoft:appservice:killprocess/1.0.0'
        description: 'Kill the main Linux worker process using an explicit instance or verified logical-zone selector.'
        duration: 'PT1M'
        parameters: [
          {
            key: 'ProcessName'
            value: 'dotnet'
          }
          {
            key: 'InstanceIds'
            value: string(selection.instanceIds)
          }
          {
            key: 'Zones'
            value: string(selection.zones)
          }
        ]
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
