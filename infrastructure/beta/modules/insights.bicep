@description('Azure region')
param location string

@description('Application Insights resource name')
param insightsName string

// ── Log Analytics Workspace (required by workspace-based App Insights) ────
resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: '${insightsName}-workspace'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'  // pay-per-GB; first 5 GB/month free
    }
    retentionInDays: 30
  }
}

// ── Application Insights ──────────────────────────────────────────────────
resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: insightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    RetentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output connectionString string = insights.properties.ConnectionString
output instrumentationKey string = insights.properties.InstrumentationKey
