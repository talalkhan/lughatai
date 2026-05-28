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

@description('CDN base URL for audio files')
param cdnBaseUrl string

@secure()
param anthropicApiKey string

@secure()
param openAiApiKey string

@secure()
param jwtSecret string

@secure()
param adminApiKey string

@secure()
param datadogApiKey string = ''

@description('Application Insights connection string for telemetry')
param appInsightsConnectionString string = ''

// ── App Service Plan (S1 Standard — supports custom domains + SSL) ──────────
resource plan 'Microsoft.Web/serverfarms@2023-01-01' = {
  name: planName
  location: location
  sku: {
    name: 'S1'
    tier: 'Standard'
    capacity: 1
  }
  kind: 'linux'
  properties: {
    reserved: true // required for Linux
  }
}

// ── Web App ────────────────────────────────────────────────────────────────
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
        { name: 'ASPNETCORE_ENVIRONMENT', value: 'Production' }
        { name: 'ConnectionStrings__Default', value: connectionString }
        { name: 'Redis__Enabled', value: 'false' }
        { name: 'Redis__Connection', value: '' }
        { name: 'AI__AnthropicApiKey', value: anthropicApiKey }
        { name: 'AI__OpenAIApiKey', value: openAiApiKey }
        { name: 'AI__BatchModel', value: 'gpt-4o-mini' }
        { name: 'AI__LiveModel', value: 'gpt-4o-mini' }
        { name: 'Azure__SpeechKey', value: speechKey }
        { name: 'Azure__SpeechRegion', value: speechRegion }
        { name: 'Azure__BlobConnection', value: blobConnection }
        { name: 'Azure__CdnBaseUrl', value: cdnBaseUrl }
        { name: 'Jwt__Secret', value: jwtSecret }
        { name: 'Jwt__Issuer', value: 'UrduMeaning' }
        { name: 'Jwt__Audience', value: 'UrduMeaning.Web' }
        { name: 'Admin__ApiKey', value: adminApiKey }
        // BatchProcessor is OFF by default — enable only for intentional bulk generation runs
        { name: 'BatchProcessor__Enabled', value: 'false' }
        // WordGeneration: live AI for words not in DB. OFF by default — bots will drain credits.
        { name: 'WordGeneration__Enabled', value: 'false' }
        { name: 'WordGeneration__RequireApprovedWord', value: 'true' }
        { name: 'RomanSearchAI__Enabled', value: 'false' }
        // Enrichment: background upgrade of core→enriched. OFF by default.
        { name: 'Enrichment__Enabled', value: 'false' }
        { name: 'Enrichment__MaxPerHour', value: '30' }
        { name: 'Datadog__ApiKey', value: datadogApiKey }
        { name: 'Datadog__ServiceName', value: 'lughatai-api' }
        // Datadog APM auto-instrumentation (set DD_AGENT_HOST if using sidecar agent)
        { name: 'DD_SERVICE', value: 'lughatai-api' }
        { name: 'DD_ENV', value: 'production' }
        { name: 'DD_VERSION', value: '1.0' }
        // Application Insights — tracks requests, dependencies (Claude/OpenAI), exceptions
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
      ]
    }
  }
}

output hostName string = app.properties.defaultHostName
output appId string = app.id
