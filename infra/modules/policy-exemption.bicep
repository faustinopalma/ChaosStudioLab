targetScope = 'resourceGroup'

param policyAssignmentId string
param policyReferenceId string
param exemptionName string
param expiresOn string

resource exemption 'Microsoft.Authorization/policyExemptions@2022-07-01-preview' = {
  name: exemptionName
  properties: {
    displayName: 'Temporary operator-approved private lab public-IP waiver'
    description: 'Single public-IP append reference on this owned network group. Finite expiry; no automatic renewal.'
    exemptionCategory: 'Waiver'
    expiresOn: expiresOn
    policyAssignmentId: policyAssignmentId
    policyDefinitionReferenceIds: [
      policyReferenceId
    ]
    resourceSelectors: [
      {
        name: 'OnlyLabPublicIps'
        selectors: [
          {
            kind: 'resourceType'
            in: [
              'Microsoft.Network/publicIPAddresses'
            ]
          }
        ]
      }
    ]
  }
}
