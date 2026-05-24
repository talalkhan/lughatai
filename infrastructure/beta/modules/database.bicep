@description('Azure region')
param location string

@description('PostgreSQL Flexible Server name (globally unique)')
param serverName string

@description('Admin username')
param adminUser string

@description('Admin password')
@secure()
param adminPassword string

// ── PostgreSQL Flexible Server — Burstable B2s ─────────────────────────────
// Burstable is ideal for beta: baseline 20% CPU, bursts to 200% for short
// spikes. ~$37/month vs ~$180/month for GeneralPurpose. Upgrade to
// GeneralPurpose D2ds_v4 when CPU credit balance is consistently depleted.
resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: adminUser
    administratorLoginPassword: adminPassword
    storage: {
      storageSizeGB: 32
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  name: 'lughatai'
  parent: server
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  name: 'AllowAzureServices'
  parent: server
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output serverFqdn string = server.properties.fullyQualifiedDomainName
@secure()
output connectionString string = 'Host=${server.properties.fullyQualifiedDomainName};Port=5432;Database=lughatai;Username=${adminUser};Password=${adminPassword};SSL Mode=Require;Trust Server Certificate=true'
