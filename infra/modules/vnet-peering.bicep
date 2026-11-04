targetScope = 'resourceGroup'

param sourceVnetName string
param remoteVnetId string
param peeringName string

resource sourceVnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: sourceVnetName
}

resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2024-05-01' = {
  parent: sourceVnet
  name: peeringName
  properties: {
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
  }
}
