@description('Azure region')
param location string

@description('Storage account name (3-24 chars, lowercase alphanumeric only)')
param storageAccountName string

// ── Storage Account ────────────────────────────────────────────────────────
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: true // audio files are public
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

// ── Blob Service ───────────────────────────────────────────────────────────
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  name: 'default'
  parent: storageAccount
}

// ── Audio Container (public blob access) ──────────────────────────────────
resource audioContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'audio'
  parent: blobService
  properties: {
    publicAccess: 'Blob'
  }
}

// A public container gives Front Door a stable anonymous HEAD probe target.
resource frontDoorHealthContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: 'frontdoor-health'
  parent: blobService
  properties: {
    publicAccess: 'Container'
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
@secure()
output connectionString string = 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
output blobHostName string = '${storageAccountName}.blob.${environment().suffixes.storage}'
output blobEndpoint string = storageAccount.properties.primaryEndpoints.blob
