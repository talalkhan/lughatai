@description('Azure region')
param location string

@description('Redis cache name (globally unique)')
param cacheName string

// ── Azure Cache for Redis (C1 Standard — 1 GB, replication, persistence) ──
resource redis 'Microsoft.Cache/redis@2023-08-01' = {
  name: cacheName
  location: location
  properties: {
    sku: {
      name: 'Standard'
      family: 'C'
      capacity: 1
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    redisConfiguration: {
      'maxmemory-policy': 'allkeys-lru'
    }
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
output connectionString string = '${redis.properties.hostName}:${redis.properties.sslPort},password=${redis.listKeys().primaryKey},ssl=True,abortConnect=False'
