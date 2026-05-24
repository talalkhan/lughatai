@description('Azure region')
param location string

@description('PostgreSQL Flexible Server name (globally unique)')
param serverName string

@description('Admin username')
param adminUser string

@description('Admin password')
@secure()
param adminPassword string

// ── PostgreSQL Flexible Server ─────────────────────────────────────────────
resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_D2ds_v4'
    tier: 'GeneralPurpose'
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

// ── Database ───────────────────────────────────────────────────────────────
resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  name: 'lughatai'
  parent: server
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ── Firewall: allow Azure services ────────────────────────────────────────
resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  name: 'AllowAzureServices'
  parent: server
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// ── Outputs ────────────────────────────────────────────────────────────────
output serverFqdn string = server.properties.fullyQualifiedDomainName
@secure()
output connectionString string = 'Host=${server.properties.fullyQualifiedDomainName};Port=5432;Database=lughatai;Username=${adminUser};Password=${adminPassword};SSL Mode=Require;Trust Server Certificate=true'
