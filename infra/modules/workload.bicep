targetScope = 'resourceGroup'

param location string
param resourceNames object
param chaosWorkspaceLocation string = 'swedencentral'
param privateDnsZoneIds array
param workloadAddressPrefix string
param appServiceIntegrationSubnetPrefix string
param privateEndpointsSubnetPrefix string
param deploymentInstanceId string
param migrationPrincipalId string
@secure()
param postgresqlAdministratorPassword string

var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

var vaultName = resourceNames.vault
var databaseName = resourceNames.postgres
var postgresZoneId = privateDnsZoneIds[1]
var vaultZoneId = privateDnsZoneIds[2]
var monitorZoneIds = [
  privateDnsZoneIds[3]
  privateDnsZoneIds[4]
  privateDnsZoneIds[5]
  privateDnsZoneIds[6]
  privateDnsZoneIds[7]
]

resource workloadVnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: 'vnet-csl-workload'
  location: location
  tags: labTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        workloadAddressPrefix
      ]
    }
    subnets: [
      {
        name: 'app-service-integration'
        properties: {
          addressPrefix: appServiceIntegrationSubnetPrefix
          delegations: [
            {
              name: 'app-service'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: privateEndpointsSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: vaultName
  location: location
  tags: labTags
  properties: {
    tenantId: tenant().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Deny'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: databaseName
  location: location
  tags: labTags
  sku: {
    name: 'Standard_D4ds_v5'
    tier: 'GeneralPurpose'
  }
  properties: {
    version: '16'
    administratorLogin: 'cslbootstrap'
    administratorLoginPassword: postgresqlAdministratorPassword
    availabilityZone: '1'
    authConfig: {
      activeDirectoryAuth: 'Enabled'
      passwordAuth: 'Disabled'
      tenantId: tenant().tenantId
    }
    highAvailability: {
      mode: 'ZoneRedundant'
      standbyAvailabilityZone: '2'
    }
    storage: {
      storageSizeGB: 128
    }
    network: {
      publicNetworkAccess: 'Disabled'
    }
  }
}

resource migrationIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-csl-migrations'
  location: location
  tags: labTags
}

module postgresEntraAdministrator 'postgres-admin.bicep' = {
  name: 'csl-postgres-entra-admin'
  params: {
    serverName: postgres.name
    principalId: migrationPrincipalId
    principalName: migrationIdentity.name
    tenantId: tenant().tenantId
  }
}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logs
  location: location
  tags: labTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.insights
  location: location
  tags: labTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    IngestionMode: 'LogAnalytics'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Disabled'
    publicNetworkAccessForQuery: 'Disabled'
  }
}

resource monitorPrivateLinkScope 'Microsoft.Insights/privateLinkScopes@2021-07-01-preview' = {
  name: resourceNames.monitorScope
  location: 'global'
  tags: labTags
  properties: {
    accessModeSettings: {
      queryAccessMode: 'PrivateOnly'
      ingestionAccessMode: 'PrivateOnly'
    }
  }
}

resource monitorWorkspaceScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: monitorPrivateLinkScope
  name: 'log-analytics'
  properties: {
    linkedResourceId: logAnalytics.id
  }
}

resource monitorApplicationInsightsScope 'Microsoft.Insights/privateLinkScopes/scopedResources@2021-07-01-preview' = {
  parent: monitorPrivateLinkScope
  name: 'application-insights'
  properties: {
    linkedResourceId: applicationInsights.id
  }
}

resource chaosWorkspace 'Microsoft.Chaos/workspaces@2026-08-01-preview' = {
  name: resourceNames.chaosWorkspace
  location: chaosWorkspaceLocation
  tags: labTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${chaosIdentity.id}': {}
    }
  }
  properties: {
    scopes: [
      resourceGroup().id
    ]
  }
}

resource postgresFailoverScenario 'Microsoft.Chaos/workspaces/scenarios@2026-08-01-preview' = {
  parent: chaosWorkspace
  name: 'postgres-forced-failover'
  properties: {
    description: 'Native forced PostgreSQL failover; execute explicitly from the PC after private baseline and cooldown gates.'
    parameters: []
    actions: [
      {
        name: 'postgres-forced-failover'
        actionId: 'urn:csci:microsoft:azurepostgresql:failover/1.0.0'
        description: 'Force failover of the lab PostgreSQL Flexible Server.'
        duration: 'PT1M'
        parameters: [
          {
            key: 'FailoverMode'
            value: '1'
          }
          {
            key: 'RestoreOnStop'
            value: 'false'
          }
          {
            key: 'SkipIneligibleServers'
            value: 'false'
          }
        ]
      }
    ]
  }
}

resource postgresFailoverConfiguration 'Microsoft.Chaos/workspaces/scenarios/configurations@2026-08-01-preview' = {
  parent: postgresFailoverScenario
  name: 'exact-lab-postgres'
  properties: {
    scenarioId: postgresFailoverScenario.id
    parameters: []
    resourceTargeting: {
      include: {
        resources: [
          postgres.id
        ]
      }
    }
  }
}

resource chaosIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-csl-chaos'
  location: location
  tags: labTags
}

resource chaosDiscoveryReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, chaosIdentity.id, 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'acdd72a7-3385-48ef-bd42-f606fba81ae7')
    principalId: chaosIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-csl-runtime'
  location: location
  tags: labTags
}

resource chaosPostgresContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(postgres.id, chaosIdentity.id, 'b24988ac-6180-42a0-ab88-20f7382dd24c')
  scope: postgres
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    principalId: chaosIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

resource privateEndpointsSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: workloadVnet
  name: 'private-endpoints'
}

resource postgresPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-csl-postgres'
  location: location
  tags: labTags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'postgresql'
        properties: {
          privateLinkServiceId: postgres.id
          groupIds: [
            'postgresqlServer'
          ]
        }
      }
    ]
  }
}

resource postgresPrivateDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: postgresPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'postgresql'
        properties: {
          privateDnsZoneId: postgresZoneId
        }
      }
    ]
  }
}

resource vaultPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-csl-key-vault'
  location: location
  tags: labTags
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'vault'
        properties: {
          privateLinkServiceId: vault.id
          groupIds: [
            'vault'
          ]
        }
      }
    ]
  }
}

resource vaultPrivateDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: vaultPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'vault'
        properties: {
          privateDnsZoneId: vaultZoneId
        }
      }
    ]
  }
}

resource monitorPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-csl-monitor'
  location: location
  tags: labTags
  dependsOn: [
    monitorWorkspaceScope
    monitorApplicationInsightsScope
  ]
  properties: {
    subnet: {
      id: privateEndpointsSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'azure-monitor'
        properties: {
          privateLinkServiceId: monitorPrivateLinkScope.id
          groupIds: [
            'azuremonitor'
          ]
        }
      }
    ]
  }
}

resource monitorPrivateDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: monitorPrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, index) in monitorZoneIds: {
      name: 'monitor-${index}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

resource postgresDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'csl-postgres-logs'
  scope: postgres
  properties: {
    workspaceId: logAnalytics.id
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

resource keyVaultSecretsUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(vault.id, runtimeIdentity.id, '4633458b-17de-408a-b874-0445c86b69e6')
  scope: vault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
    principalId: runtimeIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

output vnetId string = workloadVnet.id
output vnetName string = workloadVnet.name
output postgresId string = postgres.id
output keyVaultId string = vault.id
output postgresName string = postgres.name
output postgresHost string = postgres.properties.fullyQualifiedDomainName
output vaultName string = vault.name
output runtimeIdentityId string = runtimeIdentity.id
output runtimeClientId string = runtimeIdentity.properties.clientId
output runtimePrincipalId string = runtimeIdentity.properties.principalId
output migrationIdentityId string = migrationIdentity.id
output migrationClientId string = migrationIdentity.properties.clientId
output chaosWorkspaceName string = chaosWorkspace.name
output chaosScenarioId string = postgresFailoverScenario.id
output chaosConfigurationId string = postgresFailoverConfiguration.id
output logAnalyticsId string = logAnalytics.id
output logAnalyticsCustomerId string = logAnalytics.properties.customerId
