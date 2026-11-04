targetScope = 'resourceGroup'

param location string
param operationsLocation string = location
param deploymentInstanceId string
param operationsAddressPrefix string
param operationsSubnetPrefix string
param bastionSubnetPrefix string
param natPublicIpId string
param bastionPublicIpId string
param migrationIdentityId string
param runnerSshPublicKey string
param runnerAdminUsername string = 'csloperator'

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

var storageRegionNames = {
  italynorth: 'ItalyNorth'
  swedencentral: 'SwedenCentral'
  spaincentral: 'SpainCentral'
}

var egress = [
  { name: 'wire-server', destination: '168.63.129.16', ports: ['80', '32526'] }
  { name: 'entra', destination: 'AzureActiveDirectory', ports: ['443'] }
  { name: 'resource-manager', destination: 'AzureResourceManager', ports: ['443'] }
  { name: 'monitor', destination: 'AzureMonitor', ports: ['443'] }
  { name: 'storage', destination: 'Storage.${storageRegionNames[operationsLocation]}', ports: ['443'] }
  { name: 'bootstrap-https', destination: 'Internet', ports: ['443'] }
  { name: 'private-services', destination: 'VirtualNetwork', ports: ['443', '5432'] }
]

var outboundRules = [for (rule, index) in egress: {
  name: 'allow-${rule.name}'
  properties: {
    priority: 110 + index * 10
    protocol: 'Tcp'
    access: 'Allow'
    direction: 'Outbound'
    sourceAddressPrefix: '*'
    sourcePortRange: '*'
    destinationAddressPrefix: rule.destination
    destinationPortRanges: rule.ports
  }
}]

resource runnerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-csl-runner'
  location: location
  tags: labTags
}

resource nat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-csl-operations'
  location: operationsLocation
  tags: labTags
  sku: { name: 'Standard' }
  properties: { publicIpAddresses: [{ id: natPublicIpId }] }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-csl-operations'
  location: operationsLocation
  tags: labTags
  properties: {
    securityRules: concat([
      {
        name: 'allow-ssh-from-bastion-only'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: bastionSubnetPrefix
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '22'
        }
      }
      {
        name: 'deny-other-inbound'
        properties: {
          priority: 120
          protocol: '*'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ], outboundRules, [
      {
        name: 'deny-other-outbound'
        properties: {
          priority: 200
          protocol: '*'
          access: 'Deny'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ])
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-csl-operations'
  location: operationsLocation
  tags: labTags
  properties: {
    addressSpace: { addressPrefixes: [operationsAddressPrefix] }
    subnets: [
      {
        name: 'operations'
        properties: {
          addressPrefix: operationsSubnetPrefix
          defaultOutboundAccess: false
          natGateway: { id: nat.id }
          networkSecurityGroup: { id: nsg.id }
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: { addressPrefix: bastionSubnetPrefix }
      }
    ]
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'bas-csl-operations'
  location: operationsLocation
  tags: labTags
  sku: { name: 'Standard' }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: { id: '${vnet.id}/subnets/AzureBastionSubnet' }
          publicIPAddress: { id: bastionPublicIpId }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-csl-runner'
  location: operationsLocation
  tags: labTags
  properties: {
    ipConfigurations: [
      {
        name: 'private'
        properties: {
          subnet: { id: '${vnet.id}/subnets/operations' }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource runner 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-csl-runner'
  location: operationsLocation
  tags: labTags
  zones: ['1']
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runnerIdentity.id}': {}
      '${migrationIdentityId}': {}
    }
  }
  properties: {
    hardwareProfile: { vmSize: 'Standard_D2s_v5' }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-csl-runner'
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    osProfile: {
      computerName: 'vm-csl-runner'
      adminUsername: runnerAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: [{
            path: '/home/csloperator/.ssh/authorized_keys'
            keyData: runnerSshPublicKey
          }]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id, properties: { primary: true } }]
    }
    diagnosticsProfile: { bootDiagnostics: { enabled: true } }
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output bastionName string = bastion.name
output bastionId string = bastion.id
output outboundNatId string = nat.id
output runnerId string = runner.id
output runnerName string = runner.name
output runnerIdentityId string = runnerIdentity.id
output runnerClientId string = runnerIdentity.properties.clientId
output runnerPrincipalId string = runnerIdentity.properties.principalId
