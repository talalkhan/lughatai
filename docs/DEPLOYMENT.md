# UrduMeaning — Deployment Reference

> Last updated: 2026-05-24  
> Environment: **Beta** (production-equivalent, single region)

---

## Live URLs

| Service | URL |
|---------|-----|
| **Website** | https://urdumeaning.com |
| **API** | https://lughatai-beta-api.azurewebsites.net |
| **Frontend (direct)** | https://lughatai-beta-web.azurewebsites.net |

---

## Azure Resources

All resources live in resource group **`lughatai-beta-rg`**, region **UAE North**.

| Resource | Type | Name | Notes |
|----------|------|------|-------|
| App Service Plan | B2 Basic (2 vCores, 3.5 GB RAM, Linux) | `lughatai-beta-plan` | Shared by API + frontend — $0 extra per app |
| API Web App | App Service (Node.js → .NET 8) | `lughatai-beta-api` | ASP.NET Core 8, `WEBSITE_RUN_FROM_PACKAGE=1`, **Always On: enabled** |
| Frontend Web App | App Service (Node.js 22) | `lughatai-beta-web` | Next.js 14, startup: `npm start`, port 3000, **Always On: enabled** |
| PostgreSQL | Flexible Server B2s Burstable | `lughatai-beta-db` | v16, 32 GB storage, 7-day PITR backup |
| Blob Storage | Standard LRS | `lughataibetastorage` | Audio files + DB backups |
| Speech Services | S0 pay-per-use | `lughatai-beta-speech` | Azure TTS for Urdu/English pronunciation |

### Storage Containers

| Container | Purpose |
|-----------|---------|
| `audio` | Lazily-generated TTS audio files (EN + UR) |
| `db-backups` | Weekly automated pg_dump snapshots |

### Database

- **Host:** `lughatai-beta-db.postgres.database.azure.com`
- **Database:** `lughatai`
- **Admin user:** `lughatadmin`
- **Firewall:** Azure services only (0.0.0.0/0.0.0.0) — external access must be added temporarily
- **Words:** 45,500 definitions as of 2026-05-24

---

## DNS & Domain (Cloudflare)

Domain **`urdumeaning.com`** is managed in Cloudflare. DNS records:

| Type | Name | Value | Proxy |
|------|------|-------|-------|
| CNAME | `@` | `lughatai-beta-web.azurewebsites.net` | Proxied 🟠 |
| CNAME | `www` | `lughatai-beta-web.azurewebsites.net` | Proxied 🟠 |
| TXT | `asuid` | `89CEDEAB798B21CABF0C2ACE8310EFB6A142F73E70D2F420193393F25AF4AB58` | DNS only |
| TXT | `asuid.www` | `89CEDEAB798B21CABF0C2ACE8310EFB6A142F73E70D2F420193393F25AF4AB58` | DNS only |

Cloudflare handles SSL termination. Traffic flows:  
`Browser → Cloudflare (HTTPS) → Azure Web App (HTTPS)`

---

## CI/CD — GitHub Actions

Repository: **`talalkhan/lughatai`**

| Workflow | File | Trigger | What it does |
|----------|------|---------|--------------|
| Deploy Web | `.github/workflows/deploy-web.yml` | Push to `master` touching `web/**` | Builds Next.js, prunes dev deps, deploys to `lughatai-beta-web` |
| Backup DB | `.github/workflows/backup-db.yml` | Every Sunday 2am UTC + manual | pg_dump → gzip → Azure Blob Storage, prunes backups >12 weeks old |

### GitHub Secrets

| Secret | Used By | Description |
|--------|---------|-------------|
| `AZURE_WEB_PUBLISH_PROFILE` | deploy-web.yml | Publish profile XML for `lughatai-beta-web` |
| `AZURE_BACKUP_CREDENTIALS` | backup-db.yml | Service principal JSON (`lughatai-db-backup`) |
| `AZURE_DB_PASSWORD` | backup-db.yml | PostgreSQL admin password |

> **Rotating secrets:** Download a new publish profile from Azure Portal → `lughatai-beta-web` → Overview → Download publish profile. Update the GitHub secret via Settings → Secrets → Actions.

---

## API Environment Variables

Set as App Settings on `lughatai-beta-api` in Azure Portal (or via `az webapp config appsettings set`):

| Setting | Value / Source |
|---------|----------------|
| `ASPNETCORE_ENVIRONMENT` | `Production` |
| `ConnectionStrings__Default` | PostgreSQL connection string |
| `AI__AnthropicApiKey` | Anthropic console → API Keys |
| `AI__OpenAIApiKey` | OpenAI console → API Keys |
| `AI__BatchModel` | `claude-haiku-4-5-20251001` |
| `AI__LiveModel` | `claude-sonnet-4-6` |
| `Azure__SpeechKey` | Azure Portal → `lughatai-beta-speech` → Keys |
| `Azure__SpeechRegion` | `uaenorth` |
| `Azure__BlobConnection` | Azure Portal → `lughataibetastorage` → Access keys |
| `Jwt__Secret` | Stored in Azure App Settings (32+ char random string) |
| `Admin__ApiKey` | Stored in Azure App Settings |
| `Cors__AllowedOrigins__0` | `https://urdumeaning.com` |
| `Cors__AllowedOrigins__1` | `https://www.urdumeaning.com` |
| `Cors__AllowedOrigins__2` | `https://lughatai-beta-web.azurewebsites.net` |
| `BatchProcessor__Enabled` | `true` during generation, `false` after |
| `WEBSITE_RUN_FROM_PACKAGE` | `1` |

> **Rotating API keys:** Azure Portal → `lughatai-beta-api` → Configuration → Application settings.  
> Never put secrets in `appsettings.json` or source code.

---

## Frontend Environment Variables

Set as App Settings on `lughatai-beta-web`:

| Setting | Value |
|---------|-------|
| `NEXT_PUBLIC_API_URL` | `https://lughatai-beta-api.azurewebsites.net` |
| `NEXT_PUBLIC_SITE_URL` | `https://urdumeaning.com` |
| `NODE_ENV` | `production` |
| `WEBSITES_PORT` | `3000` |
| `SCM_DO_BUILD_DURING_DEPLOYMENT` | `false` |

---

## Database Backup & Restore

### Automated backups (primary)

The `backup-db.yml` GitHub Action runs every Sunday at 2am UTC:
1. Opens PostgreSQL firewall for the GitHub runner's IP
2. Runs `pg_dump` against Azure PostgreSQL
3. Uploads compressed snapshot to `lughataibetastorage/db-backups/word_definitions_YYYY-MM-DD.sql.gz`
4. Prunes snapshots older than 12 weeks
5. Closes the firewall rule

**Manual trigger:** GitHub → Actions → "Backup Database to Azure Blob Storage" → Run workflow

### Restore from Azure Blob (recommended)

```powershell
# Restore latest backup
.\scripts\db_restore_from_blob.ps1

# Restore specific date
.\scripts\db_restore_from_blob.ps1 -Date 2026-05-18
```

Requirements: Azure CLI logged in (`az login`), Docker running (`docker compose up -d`).  
The script handles firewall rules automatically — opens before restore, closes after.

### Restore from Git backup (legacy fallback)

The repo also contains `data/word_definitions_backup.part*.sql.gz` — a copy of the DB at last commit time.

```powershell
# To Azure PostgreSQL
.\scripts\db_restore_azure.ps1

# To local Docker PostgreSQL
.\scripts\db_restore.ps1
```

### Back up local DB to Git (legacy)

```powershell
.\scripts\db_backup.ps1
git add data\
git commit -m "backup: 45500 words"
git push
```

---

## Service Principal

**Name:** `lughatai-db-backup`  
**Client ID:** `cfad97f6-e7d8-46d0-b991-ee40ba1023e8`  
**Permissions:**
- Contributor on `lughatai-beta-rg` (manages PostgreSQL firewall rules)
- Storage Blob Data Contributor on `lughataibetastorage` (writes DB backups)

Credentials are stored in the `AZURE_BACKUP_CREDENTIALS` GitHub secret.

---

## Cost Breakdown (Beta)

| Resource | Monthly Cost (approx.) |
|----------|------------------------|
| App Service Plan B2 | ~$73 |
| PostgreSQL B2s Burstable | ~$37 |
| Blob Storage (< 1 GB) | ~$0.02 |
| Speech Services (per use) | ~$0 at beta scale |
| GitHub Actions | Free (< 2000 min/month) |
| Cloudflare | Free |
| **Total** | **~$110/month** |

> The B2 App Service Plan hosts both the API and the frontend — no extra charge for the second web app.

---

## Disaster Recovery

### Full recovery from scratch

```powershell
# 1. Provision infrastructure
az deployment group create \
  --resource-group lughatai-beta-rg \
  --template-file infrastructure/beta/main.bicep \
  --parameters ...

# 2. Apply DB migrations
cd api
dotnet ef database update --connection "<connection string>"

# 3. Restore word definitions (from Blob Storage — preferred)
.\scripts\db_restore_from_blob.ps1

# 4. Deploy API (push to master or run GitHub Action manually)
# 5. Deploy frontend (push to master or run GitHub Action manually)
# 6. Verify: curl https://lughatai-beta-api.azurewebsites.net/api/word/knowledge
```

### If Azure Blob Storage is unavailable

Restore from the Git backup:
```powershell
git pull   # get latest backup from GitHub
docker compose up -d
cd api; dotnet ef database update
cd ..; .\scripts\db_restore_azure.ps1
```

---

## Admin Operations

### Check word count
```bash
curl https://lughatai-beta-api.azurewebsites.net/api/admin/queue/status \
  -H "X-Admin-Key: <admin key from Azure app settings>"
```

### Add words to queue
```bash
curl -X POST https://lughatai-beta-api.azurewebsites.net/api/admin/queue/add \
  -H "X-Admin-Key: <admin key>" \
  -H "Content-Type: application/json" \
  -d '{"words": ["ephemeral", "solitude"], "priority": 1}'
```

### Retry failed words
```bash
curl -X POST https://lughatai-beta-api.azurewebsites.net/api/admin/queue/retry-failed \
  -H "X-Admin-Key: <admin key>"
```

### Disable batch processor (after initial generation)
```bash
az webapp config appsettings set \
  --resource-group lughatai-beta-rg \
  --name lughatai-beta-api \
  --settings BatchProcessor__Enabled=false
```
