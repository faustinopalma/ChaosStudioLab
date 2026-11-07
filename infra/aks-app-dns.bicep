resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = { name: 'csl.internal' }
resource api 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: zone
  name: 'api'
  properties: { ttl: 60, aRecords: [{ ipv4Address: '10.91.3.240' }] }
}
