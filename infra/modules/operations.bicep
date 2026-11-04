targetScope = 'resourceGroup'

param location string
param deploymentInstanceId string
param privateDnsZoneIds array
param automationPrivateDnsZoneId string
param operationsAddressPrefix string
param operationsSubnetPrefix string
param privateEndpointsSubnetPrefix string
param bastionSubnetPrefix string
param natPublicIpId string
param bastionPublicIpId string
param migrationIdentityId string
param runnerSshPublicKey string

@description('Linux administrator account used for the private operations VMs.')
param adminUsername string = 'csloperator'

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

var suffix = uniqueString(resourceGroup().id)
var storageName = take('csl${suffix}', 24)
var automationName = 'aa-csl-control'
var workerGroupName = 'hrg-csl-control'
var sshPublicKeys = [
  {
    path: '/home/${adminUsername}/.ssh/authorized_keys'
    keyData: runnerSshPublicKey
  }
]

resource outboundNat 'Microsoft.Network/natGateways@2024-05-01' = {
  name: 'nat-csl-operations'
  location: location
  tags: labTags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIpId
      }
    ]
  }
}

resource operationsNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-csl-operations'
  location: location
  tags: labTags
  properties: {
    securityRules: [
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
        name: 'deny-other-ssh'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Deny'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
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
      {
        name: 'allow-azure-wire-server'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '168.63.129.16'
          destinationPortRanges: [
            '80'
            '32526'
          ]
        }
      }
      {
        name: 'allow-automation-hybrid-workers'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'GuestAndHybridManagement'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-entra'
        properties: {
          priority: 130
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureActiveDirectory'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-resource-manager'
        properties: {
          priority: 140
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureResourceManager'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-azure-monitor'
        properties: {
          priority: 150
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureMonitor'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-region-storage'
        properties: {
          priority: 160
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage.${location == 'northeurope' ? 'NorthEurope' : 'SwedenCentral'}'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-bootstrap-https'
        properties: {
          priority: 170
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Internet'
          destinationPortRange: '443'
        }
      }
      {
        name: 'allow-private-service-traffic'
        properties: {
          priority: 180
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: 'VirtualNetwork'
          destinationPortRanges: [
            '443'
            '5432'
          ]
        }
      }
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
    ]
  }
}

resource operationsVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-csl-operations'
  location: location
  tags: labTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        operationsAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'operations'
        properties: {
          addressPrefix: operationsSubnetPrefix
          defaultOutboundAccess: false
          natGateway: {
            id: outboundNat.id
          }
          networkSecurityGroup: {
            id: operationsNsg.id
          }
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
    ]
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'bas-csl-operations'
  location: location
  tags: labTags
  sku: {
    name: 'Standard'
  }
  properties: {
    enableTunneling: true
    ipConfigurations: [
      {
        name: 'bastion-ipconfig'
        properties: {
          subnet: {
            id: '${operationsVnet.id}/subnets/AzureBastionSubnet'
          }
          publicIPAddress: {
            id: bastionPublicIpId
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource controlStorage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  tags: labTags
  sku: {
    name: 'Standard_ZRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    publicNetworkAccess: 'Disabled'
    supportsHttpsTrafficOnly: true
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: controlStorage
  name: 'default'
}

resource stateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'control-state'
  properties: {
    publicAccess: 'None'
  }
}

resource controlIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-csl-control'
  location: location
  tags: labTags
}

resource runnerIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-csl-runner'
  location: location
  tags: labTags
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationName
  location: location
  tags: labTags
  properties: {
    publicNetworkAccess: false
    sku: {
      name: 'Basic'
    }
  }
}

resource workerGroup 'Microsoft.Automation/automationAccounts/hybridRunbookWorkerGroups@2024-10-23' = {
  parent: automationAccount
  name: workerGroupName
  properties: {}
}

resource controlStoragePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-csl-control-storage'
  location: location
  tags: labTags
  properties: {
    subnet: {
      id: '${operationsVnet.id}/subnets/private-endpoints'
    }
    privateLinkServiceConnections: [
      {
        name: 'control-storage-blob'
        properties: {
          privateLinkServiceId: controlStorage.id
          groupIds: [
            'blob'
          ]
        }
      }
    ]
  }
}

resource controlStoragePrivateDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: controlStoragePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: {
          privateDnsZoneId: privateDnsZoneIds[4]
        }
      }
    ]
  }
}

resource automationPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-csl-automation'
  location: location
  tags: labTags
  properties: {
    subnet: {
      id: '${operationsVnet.id}/subnets/private-endpoints'
    }
    privateLinkServiceConnections: [
      {
        name: 'automation-dsc-hybrid-worker'
        properties: {
          privateLinkServiceId: automationAccount.id
          groupIds: [
            'DSCAndHybridWorker'
          ]
        }
      }
    ]
  }
}

resource automationPrivateDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: automationPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'automation'
        properties: {
          privateDnsZoneId: automationPrivateDnsZoneId
        }
      }
    ]
  }
}

resource controlStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(controlStorage.id, controlIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: controlStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: controlIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource runnerControlStorageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(controlStorage.id, runnerIdentity.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: controlStorage
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
    principalId: runnerIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource runnerNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-csl-runner'
  location: location
  tags: labTags
  properties: {
    ipConfigurations: [
      {
        name: 'private'
        properties: {
          subnet: {
            id: '${operationsVnet.id}/subnets/operations'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource worker1Nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-csl-worker-1'
  location: location
  tags: labTags
  properties: {
    ipConfigurations: [
      {
        name: 'private'
        properties: {
          subnet: {
            id: '${operationsVnet.id}/subnets/operations'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource worker2Nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-csl-worker-2'
  location: location
  tags: labTags
  properties: {
    ipConfigurations: [
      {
        name: 'private'
        properties: {
          subnet: {
            id: '${operationsVnet.id}/subnets/operations'
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

resource runner 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-csl-runner'
  location: location
  tags: labTags
  zones: [
    '1'
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runnerIdentity.id}': {}
      '${migrationIdentityId}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v5'
    }
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
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-csl-runner'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: sshPublicKeys
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: runnerNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource worker1 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-csl-worker-1'
  location: location
  tags: labTags
  zones: [
    '1'
  ]
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${controlIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v5'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-csl-worker-1'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-csl-worker-1'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: sshPublicKeys
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: worker1Nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource worker2 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: 'vm-csl-worker-2'
  location: location
  tags: labTags
  zones: [
    '2'
  ]
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: {
      '${controlIdentity.id}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v5'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: 'osdisk-csl-worker-2'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'vm-csl-worker-2'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        provisionVMAgent: true
        ssh: {
          publicKeys: sshPublicKeys
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: worker2Nic.id
          properties: {
            primary: true
          }
        }
      ]
    }
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

output vnetId string = operationsVnet.id
output vnetName string = operationsVnet.name
output bastionName string = bastion.name
output bastionId string = bastion.id
output outboundNatId string = outboundNat.id
output controlStorageId string = controlStorage.id
output storageName string = controlStorage.name
output controlIdentityId string = controlIdentity.id
output controlClientId string = controlIdentity.properties.clientId
output controlPrincipalId string = controlIdentity.properties.principalId
output automationName string = automationAccount.name
output automationHybridServiceUrl string = automationAccount.properties.automationHybridServiceUrl
output automationPrivateEndpointId string = automationPrivateEndpoint.id
output workerGroupName string = workerGroup.name
output runnerId string = runner.id
output runnerName string = runner.name
output runnerIdentityId string = runnerIdentity.id
output runnerClientId string = runnerIdentity.properties.clientId
output runnerPrincipalId string = runnerIdentity.properties.principalId
output worker1Id string = worker1.id
output worker1Name string = worker1.name
output worker2Id string = worker2.id
output worker2Name string = worker2.name
