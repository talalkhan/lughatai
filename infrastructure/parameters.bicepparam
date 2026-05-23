using './main.bicep'

// ── Deploy command ─────────────────────────────────────────────────────────
// az group create --name lughatai-prod-rg --location eastus
// az deployment group create \
//   --resource-group lughatai-prod-rg \
//   --template-file main.bicep \
//   --parameters parameters.bicepparam

param environment = 'prod'
param location = 'eastus'
param prefix = 'lughatai'
param dbAdminUser = 'lughatadmin'

// Secrets — supply via --parameters or Azure Key Vault references
// Do NOT commit real values here.
param dbAdminPassword = ''       // az keyvault secret show --name db-password ...
param anthropicApiKey = ''
param openAiApiKey = ''
param jwtSecret = ''             // min 32 chars
param adminApiKey = ''
param datadogApiKey = ''
