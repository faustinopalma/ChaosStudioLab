targetScope = 'subscription'

@allowed(['italynorth', 'swedencentral', 'spaincentral'])
param location string
param deploymentInstanceId string
@minLength(3)
@maxLength(3)
param resourceGroupNames array
param policyAssignmentId string
param policyReferenceId string
param exemptionName string
param exemptionExpiresOn string

resource groups 'Microsoft.Resources/resourceGroups@2024-03-01' = [for name in resourceGroupNames: {
  name: name
  location: location
  tags: {
    project: 'ChaosStudioLab'
    labId: 'lab-dev01'
    environment: 'nonproduction'
    owner: 'lab-operator'
    deploymentInstanceId: deploymentInstanceId
  }
}]

module exemption 'modules/policy-exemption.bicep' = {
  name: 'csl-approved-network-exemption'
  scope: resourceGroup(resourceGroupNames[0])
  dependsOn: [
    groups
  ]
  params: {
    policyAssignmentId: policyAssignmentId
    policyReferenceId: policyReferenceId
    exemptionName: exemptionName
    expiresOn: exemptionExpiresOn
  }
}
