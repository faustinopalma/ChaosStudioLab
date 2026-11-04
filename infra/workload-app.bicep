targetScope = 'resourceGroup'

param location string
@description('Repository path inside the lab-owned private ACR.')
@minLength(1)
param applicationRepository string

@description('Immutable sha256 digest of an image already pushed to the lab-owned ACR.')
@minLength(71)
@maxLength(71)
param applicationImageDigest string
param deploymentInstanceId string

var suffix = uniqueString(resourceGroup().id)
var registryName = take('csl${suffix}', 50)
var runtimeIdentityName = 'id-csl-runtime'
var environmentName = 'cae-csl-workload'
var applicationInsightsName = 'appi-csl-${suffix}'
var labTags = {
  project: 'ChaosStudioLab'
  labId: 'lab-dev01'
  environment: 'nonproduction'
  owner: 'lab-operator'
  deploymentInstanceId: deploymentInstanceId
}

resource registry 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: registryName
}

resource containerEnvironment 'Microsoft.App/managedEnvironments@2026-07-01' existing = {
  name: environmentName
}

resource runtimeIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' existing = {
  name: runtimeIdentityName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource vault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: take('csl-kv-${suffix}', 24)
}

resource postgres 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' existing = {
  name: take('csl-pg-${suffix}', 63)
}

resource application 'Microsoft.App/containerApps@2024-03-01' = {
  name: 'ca-csl-api'
  location: location
  tags: labTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${runtimeIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnvironment.id
    workloadProfileName: 'D4'
    configuration: {
      activeRevisionsMode: 'Single'
      secrets: [
        {
          name: 'diagnostics-token'
          keyVaultUrl: '${vault.properties.vaultUri}secrets/diagnostics-token'
          identity: runtimeIdentity.id
        }
      ]
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: [
        {
          server: registry.properties.loginServer
          identity: runtimeIdentity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: '${registry.properties.loginServer}/${applicationRepository}@${applicationImageDigest}'
          resources: {
            cpu: 1
            memory: '2Gi'
          }
          env: [
            {
              name: 'AZURE_CLIENT_ID'
              value: runtimeIdentity.properties.clientId
            }
            {
              name: 'ConnectionStrings__Postgres'
              value: 'Host=${postgres.properties.fullyQualifiedDomainName};Database=csl;Username=id-csl-runtime;SSL Mode=VerifyFull'
            }
            {
              name: 'Diagnostics__Token'
              secretRef: 'diagnostics-token'
            }
            {
              name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
              value: applicationInsights.properties.ConnectionString
            }
          ]
          probes: [
            {
              type: 'Startup'
              httpGet: {
                path: '/health/live'
                port: 8080
              }
              periodSeconds: 5
              failureThreshold: 30
            }
            {
              type: 'Liveness'
              httpGet: {
                path: '/health/live'
                port: 8080
              }
              periodSeconds: 10
              failureThreshold: 3
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health/ready'
                port: 8080
              }
              periodSeconds: 5
              failureThreshold: 2
              successThreshold: 1
              timeoutSeconds: 4
            }
          ]
        }
      ]
      scale: {
        minReplicas: 6
        maxReplicas: 12
      }
    }
  }
}

output applicationId string = application.id
output applicationFqdn string = application.properties.configuration.ingress.fqdn
