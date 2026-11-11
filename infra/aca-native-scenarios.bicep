param location string
param deploymentInstanceId string
param workspaceName string
param chaosIdentityId string
param scopes array
param postgresResourceId string

resource workspace 'Microsoft.Chaos/workspaces@2026-08-01-preview' = {
  name: workspaceName
  location: location
  tags: { project: 'ChaosStudioLab', labId: 'lab-dev01', environment: 'nonproduction', owner: 'lab-operator', deploymentInstanceId: deploymentInstanceId }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${chaosIdentityId}': {} } }
  properties: { scopes: scopes }
}
resource scenario 'Microsoft.Chaos/workspaces/scenarios@2026-08-01-preview' = {
  parent: workspace
  name: 'aca-postgres-forced-failover'
  properties: {
    description: 'Owned private PostgreSQL forced failover under Container Apps load; independent effect evidence required.'
    parameters: []
    actions: [{
      name: 'native-fault'
      actionId: 'urn:csci:microsoft:azurepostgresql:failover/1.0.0'
      duration: 'PT1M'
      parameters: [{ key: 'FailoverMode', value: '1' }, { key: 'RestoreOnStop', value: 'false' }, { key: 'SkipIneligibleServers', value: 'false' }]
    }]
  }
}
resource configuration 'Microsoft.Chaos/workspaces/scenarios/configurations@2026-08-01-preview' = {
  parent: scenario
  name: 'exact-owned-targets'
  properties: { scenarioId: scenario.id, parameters: [], resourceTargeting: { include: { resources: [postgresResourceId] } } }
}
output workspaceId string = workspace.id
output configurations array = [{ name: scenario.name, id: configuration.id, targets: [postgresResourceId] }]
