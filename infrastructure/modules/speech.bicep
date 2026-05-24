@description('Azure region')
param location string

@description('Cognitive Services account name')
param speechName string

// ── Azure Cognitive Services — Speech ──────────────────────────────────────
resource speechService 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: speechName
  location: location
  kind: 'SpeechServices'
  sku: {
    name: 'S0' // Standard tier — required for neural voices (Uzma, Jenny)
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
@secure()
output key string = speechService.listKeys().key1
output endpoint string = speechService.properties.endpoint
