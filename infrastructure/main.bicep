@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

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

@secure()
@description('Datadog API key')
param datadogApiKey string = ''

// ── Shared naming ──────────────────────────────────────────────────────────
var resourcePrefix = '${prefix}-${environment}'
var storageAccountName = '${prefix}${environment}storage' // no hyphens, max 24 chars

// ── Modules ────────────────────────────────────────────────────────────────

module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    location: location
    storageAccountName: storageAccountName
  }
}

module database 'modules/database.bicep' = {
  name: 'database'
  params: {
    location: location
    serverName: '${resourcePrefix}-db'
    adminUser: dbAdminUser
    adminPassword: dbAdminPassword
  }
}

module redis 'modules/redis.bicep' = {
  name: 'redis'
  params: {
    location: location
    cacheName: '${resourcePrefix}-redis'
  }
}

module speech 'modules/speech.bicep' = {
  name: 'speech'
  params: {
    location: location
    speechName: '${resourcePrefix}-speech'
  }
}

module cdn 'modules/cdn.bicep' = {
  name: 'edge'
  params: {
    profileName: '${resourcePrefix}-fd'
    endpointName: '${resourcePrefix}-audio'
    storageHostName: storage.outputs.blobHostName
  }
}

// ── Application Insights — free up to 5 GB/month ─────────────────────────
module insights 'modules/insights.bicep' = {
  name: 'insights'
  params: {
    location: location
    insightsName: '${resourcePrefix}-insights'
  }
}

module appService 'modules/appservice.bicep' = {
  name: 'appservice'
  params: {
    location: location
    planName: '${resourcePrefix}-plan'
    appName: '${resourcePrefix}-api'
    connectionString: database.outputs.connectionString
    redisConnection: redis.outputs.connectionString
    blobConnection: storage.outputs.connectionString
    speechKey: speech.outputs.key
    speechRegion: location
    cdnBaseUrl: cdn.outputs.endpointUrl
    anthropicApiKey: anthropicApiKey
    openAiApiKey: openAiApiKey
    jwtSecret: jwtSecret
    adminApiKey: adminApiKey
    datadogApiKey: datadogApiKey
    appInsightsConnectionString: insights.outputs.connectionString
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────

output apiUrl string = 'https://${appService.outputs.hostName}'
output dbServerFqdn string = database.outputs.serverFqdn
output redisFqdn string = redis.outputs.hostName
output cdnUrl string = cdn.outputs.endpointUrl
output storageAccountName string = storageAccountName
output appInsightsName string = '${resourcePrefix}-insights'
