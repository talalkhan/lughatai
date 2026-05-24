@description('Environment name')
param environment string = 'beta'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Short prefix for resource naming')
param prefix string = 'lughatai'

@description('PostgreSQL admin username')
param dbAdminUser string = 'lughatadmin'

@secure()
@description('PostgreSQL admin password')
param dbAdminPassword string

@secure()
@description('Anthropic API key')
param anthropicApiKey string

@secure()
@description('OpenAI API key (fallback)')
param openAiApiKey string

@secure()
@description('JWT signing secret (32+ chars)')
param jwtSecret string

@secure()
@description('Admin API key for internal endpoints')
param adminApiKey string

// ── Naming ─────────────────────────────────────────────────────────────────
var resourcePrefix     = '${prefix}-${environment}'
var storageAccountName = '${prefix}${environment}storage'

// ── Storage (shared module — no changes needed) ───────────────────────────
module storage '../modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    storageAccountName: storageAccountName
  }
}

// ── Database — Burstable B2s (~$37/month vs $180/month GeneralPurpose) ─────
module database 'modules/database.bicep' = {
  name: 'database'
  params: {
    location: location
    serverName: '${resourcePrefix}-db'
    adminUser: dbAdminUser
    adminPassword: dbAdminPassword
  }
}

// ── Speech — S0 pay-per-use (near-zero cost at beta scale) ────────────────
module speech 'modules/speech.bicep' = {
  name: 'speech'
  params: {
    location: location
    speechName: '${resourcePrefix}-speech'
  }
}

// ── App Service — B2 Basic, no Redis, direct Blob URLs ────────────────────
module appService 'modules/appservice.bicep' = {
  name: 'appservice'
  params: {
    location: location
    planName: '${resourcePrefix}-plan'
    appName:  '${resourcePrefix}-api'
    connectionString: database.outputs.connectionString
    blobConnection:   storage.outputs.connectionString
    speechKey:        speech.outputs.key
    speechRegion:     location
    blobBaseUrl:      storage.outputs.blobEndpoint
    anthropicApiKey:  anthropicApiKey
    openAiApiKey:     openAiApiKey
    jwtSecret:        jwtSecret
    adminApiKey:      adminApiKey
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
output apiUrl            string = 'https://${appService.outputs.hostName}'
output dbServerFqdn      string = database.outputs.serverFqdn
output storageAccountName string = storageAccountName
output blobEndpoint      string = storage.outputs.blobEndpoint

// Next steps after deploy:
//   1. dotnet ef database update --connection "<connectionString output above>"
//   2. .\scripts\db_restore.ps1  (restore word definitions from backup)
//   3. Set NEXT_PUBLIC_API_URL=<apiUrl> on Vercel
//   4. Point urdumeaning.com DNS to <apiUrl hostname>
//   5. After initial word generation: set BatchProcessor__Enabled=false
