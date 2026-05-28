@description('Azure region')
param location string

@description('App Service Plan name')
param planName string

@description('Web App name')
param appName string

@description('PostgreSQL connection string')
@secure()
param connectionString string

@description('Azure Blob Storage connection string')
@secure()
param blobConnection string

@description('Azure Speech service key')
@secure()
param speechKey string

@description('Azure Speech service region')
param speechRegion string

@description('Direct Blob Storage base URL for audio files (no CDN at beta)')
param blobBaseUrl string

@secure()
param anthropicApiKey string

@secure()
param openAiApiKey string

@secure()
param jwtSecret string

@secure()
param adminApiKey string

@description('Application Insights connection string for telemetry')
param appInsightsConnectionString string = ''

// ── App Service Plan — B2 Basic ────────────────────────────────────────────
// B2: 2 vCores, 3.5 GB RAM — more than S1 (1 vCore, 1.75 GB) at half the cost.
// No auto-scaling or deployment slots; upgrade to S1/S2 when traffic demands it.
resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  sku: {
    name: 'B2'
    tier: 'Basic'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

resource app 'Microsoft.Web/sites@2023-01-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|8.0'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      appSettings: [
        { name: 'ASPNETCORE_ENVIRONMENT',          value: 'Production' }
        { name: 'ConnectionStrings__Default',       value: connectionString }
        // Redis is not provisioned for beta — app falls back to PostgreSQL
        { name: 'Redis__Connection',               value: '' }
        { name: 'AI__AnthropicApiKey',             value: anthropicApiKey }
        { name: 'AI__OpenAIApiKey',                value: openAiApiKey }
        { name: 'AI__BatchModel',                  value: 'gpt-4o-mini' }
        { name: 'AI__LiveModel',                   value: 'claude-sonnet-4-6' }
        { name: 'Azure__SpeechKey',                value: speechKey }
        { name: 'Azure__SpeechRegion',             value: speechRegion }
        { name: 'Azure__BlobConnection',           value: blobConnection }
        // No CDN — serve audio direct from Blob Storage
        { name: 'Azure__CdnBaseUrl',               value: blobBaseUrl }
        { name: 'Jwt__Secret',                     value: jwtSecret }
        { name: 'Admin__ApiKey',                   value: adminApiKey }
        { name: 'Cors__AllowedOrigins__0',         value: 'https://urdumeaning.com' }
        { name: 'Cors__AllowedOrigins__1',         value: 'https://www.urdumeaning.com' }
        { name: 'ASPNETCORE_AllowedHosts',         value: 'urdumeaning.com;www.urdumeaning.com;${appName}.azurewebsites.net' }
        // BatchProcessor is OFF by default — enable only for intentional bulk generation runs
        { name: 'BatchProcessor__Enabled',              value: 'false' }
        // WordGeneration: live AI for words not in DB. OFF by default — bots will drain credits.
        // Set to 'true' only when intentionally allowing new word generation.
        { name: 'WordGeneration__Enabled',              value: 'true' }
        // Enrichment: background upgrade of core→enriched. OFF by default — same reason.
        { name: 'Enrichment__Enabled',                  value: 'false' }
        { name: 'Enrichment__MaxPerHour',               value: '30' }
        // Application Insights — tracks requests, dependencies (Claude/OpenAI), exceptions
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'WEBSITE_RUN_FROM_PACKAGE',             value: '1' }
      ]
    }
  }
}

output hostName string = app.properties.defaultHostName
output appId string = app.id
