@description('Azure region')
param location string

@description('App Service Plan name')
param planName string

@description('Web App name')
param appName string

@description('PostgreSQL connection string')
@secure()
param connectionString string

@description('Redis connection string')
@secure()
param redisConnection string

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
        { name: 'Redis__Connection', value: redisConnection }
        { name: 'AI__AnthropicApiKey', value: anthropicApiKey }
        { name: 'AI__OpenAIApiKey', value: openAiApiKey }
        { name: 'AI__BatchModel', value: 'claude-haiku-4-5-20251001' }
        { name: 'AI__LiveModel', value: 'claude-sonnet-4-6' }
        { name: 'Azure__SpeechKey', value: speechKey }
        { name: 'Azure__SpeechRegion', value: speechRegion }
        { name: 'Azure__BlobConnection', value: blobConnection }
        { name: 'Azure__CdnBaseUrl', value: cdnBaseUrl }
        { name: 'Jwt__Secret', value: jwtSecret }
        { name: 'Admin__ApiKey', value: adminApiKey }
        { name: 'BatchProcessor__Enabled', value: 'true' }
        { name: 'Datadog__ApiKey', value: datadogApiKey }
        { name: 'Datadog__ServiceName', value: 'lughatai-api' }
        // Datadog APM auto-instrumentation (set DD_AGENT_HOST if using sidecar agent)
        { name: 'DD_SERVICE', value: 'lughatai-api' }
        { name: 'DD_ENV', value: 'production' }
        { name: 'DD_VERSION', value: '1.0' }
        { name: 'WEBSITE_RUN_FROM_PACKAGE', value: '1' }
      ]
    }
  }
}

output hostName string = app.properties.defaultHostName
output appId string = app.id
