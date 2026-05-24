@description('Azure region')
param location string

@description('Cognitive Services account name')
param speechName string

// ── Azure Cognitive Services — Speech (S0 pay-per-use) ────────────────────
// S0 charges per character synthesised. At beta scale (thousands of unique
// words, audio generated once and cached forever in Blob Storage) cost is
// negligible — typically < $5/month.
resource speechService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: speechName
  location: location
  kind: 'SpeechServices'
  sku: {
    name: 'S0'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

@secure()
output key string = speechService.listKeys().key1
output endpoint string = speechService.properties.endpoint
