param location string
param deploymentInstanceId string
param environmentId string
param runtimeIdentityId string
param runtimeClientId string
param registryHost string
param imageReference string
param postgresHost string
param sharedCacheHost string
param sourceRevision string
@secure()
param diagnosticsToken string

var tags = { project: 'ChaosStudioLab', labId: 'lab-dev01', environment: 'nonproduction', owner: 'lab-operator', deploymentInstanceId: deploymentInstanceId }
resource app 'Microsoft.App/containerApps@2026-07-01' = {
  name: 'ca-csl-api'
  location: location
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${runtimeIdentityId}': {} } }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: { external: true, targetPort: 8080, transport: 'http', allowInsecure: false, traffic: [{ latestRevision: true, weight: 100 }] }
      registries: [{ server: registryHost, identity: runtimeIdentityId }]
      secrets: [{ name: 'diagnostics-token', value: diagnosticsToken }]
    }
    template: {
      containers: [{
        name: 'api'
        image: imageReference
        resources: { cpu: json('1.0'), memory: '2Gi' }
        env: [
          { name: 'ASPNETCORE_URLS', value: 'http://+:8080' }
          { name: 'Kestrel__EndpointDefaults__Protocols', value: 'Http1' }
          { name: 'Orders__CacheImmutableReads', value: 'true' }
          { name: 'Orders__SharedCacheHost', value: sharedCacheHost }
          { name: 'ConnectionStrings__Postgres', value: 'Host=${postgresHost};Database=csl;Username=id-csl-runtime' }
          { name: 'Diagnostics__Token', secretRef: 'diagnostics-token' }
          { name: 'AZURE_CLIENT_ID', value: runtimeClientId }
          { name: 'LAB_SOURCE_REVISION', value: sourceRevision }
        ]
        probes: [
          { type: 'Startup', httpGet: { path: '/health/live', port: 8080 }, initialDelaySeconds: 3, periodSeconds: 3, timeoutSeconds: 2, failureThreshold: 10 }
          { type: 'Readiness', httpGet: { path: '/health/serving', port: 8080 }, periodSeconds: 2, timeoutSeconds: 1, failureThreshold: 2, successThreshold: 1 }
          { type: 'Liveness', httpGet: { path: '/health/live', port: 8080 }, periodSeconds: 10, timeoutSeconds: 2, failureThreshold: 3 }
        ]
      }]
      scale: { minReplicas: 6, maxReplicas: 6 }
    }
  }
}
output app object = { id: app.id, name: app.name, fqdn: app.properties.configuration.ingress.fqdn, latestRevisionName: app.properties.latestRevisionName }
