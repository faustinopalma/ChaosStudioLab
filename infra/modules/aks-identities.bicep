param location string
param deploymentInstanceId string
param names array = ['id-csl-runtime', 'id-csl-migrations', 'id-csl-chaos', 'id-csl-aks', 'id-csl-kubelet']

var tags = { project: 'ChaosStudioLab', labId: 'lab-dev01', environment: 'nonproduction', owner: 'lab-operator', deploymentInstanceId: deploymentInstanceId }
resource identities 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = [for name in names: {
  name: name
  location: location
  tags: tags
}]
output identities array = [for (name, i) in names: { name: name, id: identities[i].id, clientId: identities[i].properties.clientId, principalId: identities[i].properties.principalId }]
