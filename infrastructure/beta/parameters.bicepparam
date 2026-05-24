using './main.bicep'

// ── Deploy command ─────────────────────────────────────────────────────────
// az group create --name lughatai-beta-rg --location uaenorth
//
// az deployment group create \
//   --resource-group lughatai-beta-rg \
//   --template-file infrastructure/beta/main.bicep \
//   --parameters infrastructure/beta/parameters.bicepparam \
//   --parameters \
//     dbAdminPassword="<strong-password-min-8-chars>" \
//     anthropicApiKey="sk-ant-..." \
//     openAiApiKey="sk-..." \
//     jwtSecret="<32-char-random-string>" \
//     adminApiKey="<32-char-random-string>"

param environment = 'beta'
param location    = 'uaenorth'
param prefix      = 'lughatai'
param dbAdminUser = 'lughatadmin'

// Secrets — always pass via --parameters flag, never commit real values here.
param dbAdminPassword = ''
param anthropicApiKey = ''
param openAiApiKey    = ''
param jwtSecret       = ''
param adminApiKey     = ''
