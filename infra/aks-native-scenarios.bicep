param location string
param deploymentInstanceId string
param workspaceName string
param chaosIdentityId string
param scopes array
param exactNodeScaleSetId string
param zoneScaleSetIds array
param selectedLogicalZone string
param postgresResourceId string

resource workspace 'Microsoft.Chaos/workspaces@2026-08-01-preview' = {
  name: workspaceName
  location: location
  tags: { project: 'ChaosStudioLab', labId: 'lab-dev01', environment: 'nonproduction', owner: 'lab-operator', deploymentInstanceId: deploymentInstanceId }
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${chaosIdentityId}': {} } }
  properties: { scopes: scopes }
}
var definitions = [
  { name: 'aks-exact-node-shutdown', targets: [exactNodeScaleSetId], urn: 'urn:csci:microsoft:virtualmachinescaleset:shutdown/1.0.0', duration: 'PT7M', parameters: [{ key: 'GracefulShutdown', value: 'false' }, { key: 'Zones', value: '[]' }] }
  { name: 'aks-selected-zone-shutdown', targets: zoneScaleSetIds, urn: 'urn:csci:microsoft:virtualmachinescaleset:shutdown/1.0.0', duration: 'PT7M', parameters: [{ key: 'GracefulShutdown', value: 'false' }, { key: 'Zones', value: string([selectedLogicalZone]) }] }
  { name: 'aks-postgres-forced-failover', targets: [postgresResourceId], urn: 'urn:csci:microsoft:azurepostgresql:failover/1.0.0', duration: 'PT1M', parameters: [{ key: 'FailoverMode', value: '1' }, { key: 'RestoreOnStop', value: 'false' }, { key: 'SkipIneligibleServers', value: 'false' }] }
]
resource scenarios 'Microsoft.Chaos/workspaces/scenarios@2026-08-01-preview' = [for definition in definitions: {
  parent: workspace
  name: definition.name
  properties: { description: 'Owned deterministic AKS node infrastructure or private PostgreSQL fault; independent effect evidence required.', parameters: [], actions: [{ name: 'native-fault', actionId: definition.urn, duration: definition.duration, parameters: definition.parameters }] }
}]
resource configurations 'Microsoft.Chaos/workspaces/scenarios/configurations@2026-08-01-preview' = [for (definition, i) in definitions: {
  parent: scenarios[i]
  name: 'exact-owned-targets'
  properties: { scenarioId: scenarios[i].id, parameters: [], resourceTargeting: { include: { resources: definition.targets } } }
}]
output workspaceId string = workspace.id
output configurations array = [for (definition, i) in definitions: { name: definition.name, id: configurations[i].id, targets: definition.targets }]
