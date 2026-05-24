# UrduMeaning — Beta Infrastructure Plan

**Status:** In Progress — ready to deploy  
**Region:** UAE North (`uaenorth`)  
**Goal:** Minimum viable Azure stack that serves real traffic within milliseconds, at the lowest monthly cost, with a clear upgrade path as the user base grows.

---

## Decision Summary

The full production Bicep (`infrastructure/main.bicep`) provisions 6 Azure services
totalling ~$350/month. For a beta launch with an unknown user base, most of that spend
is premature. This document defines a 3-service stack (~$65/month) that meets every
performance target and can be upgraded one service at a time as traffic grows.

| Service | Full Prod | Beta | Reason for exclusion |
|---|---|---|---|
| PostgreSQL Flexible Server | ✅ GeneralPurpose D2ds_v4 | ✅ Burstable B2s | Downgraded tier only |
| App Service | ✅ S1 Standard | ✅ B2 Basic | Downgraded tier only |
| Blob Storage | ✅ | ✅ | Audio files — cheap, needed day 1 |
| Azure Speech (TTS) | ✅ S0 | ✅ S0 (pay-per-use) | Near-zero cost at beta scale |
| Redis Cache | ✅ C1 Standard | ❌ | See performance analysis below |
| Front Door CDN | ✅ Standard | ❌ | Direct Blob URLs work fine at beta scale |

**Frontend:** Deployed to Vercel (free tier). Not part of this Bicep.

---

## Cost Breakdown

### Beta stack (~$65–70/month)

| Service | SKU | Est. monthly cost |
|---|---|---|
| PostgreSQL Flexible Server | Burstable B2s, 32 GB | ~$37 |
| App Service | B2 Basic (2 vCores, 3.5 GB) | ~$26 |
| Blob Storage | Standard LRS, Hot | ~$2 |
| Azure Speech | S0 pay-per-use | ~$1–5 |
| **Total** | | **~$66–70** |

### Full production stack (~$350+/month)

| Service | SKU | Est. monthly cost |
|---|---|---|
| PostgreSQL Flexible Server | GeneralPurpose D2ds_v4, 32 GB | ~$180 |
| App Service | S1 Standard | ~$73 |
| Redis Cache | C1 Standard 1 GB | ~$55 |
| Azure Front Door | Standard | ~$35 + usage |
| Blob Storage | Standard LRS, Hot | ~$2 |
| Azure Speech | S0 pay-per-use | ~$5 |
| **Total** | | **~$350+** |

**Beta saves ~$280/month** — meaningful before the product has revenue.

---

## Architecture

```
User
 │
 ├─── Next.js (Vercel — free)
 │         │
 │         └── HTTPS → Azure App Service B2
 │                          │
 │                          ├── PostgreSQL Flexible Server B2s
 │                          │   (word definitions, corrections, users)
 │                          │
 │                          ├── Azure Blob Storage
 │                          │   (audio .mp3 files, lazy-generated)
 │                          │
 │                          └── Azure Speech S0
 │                              (TTS on first audio play per word)
 │
 └─── Audio files: direct Blob Storage HTTPS URL
      (no CDN — acceptable latency at beta scale)
```

---

## Why Removing Redis Is Safe for Beta

The app's performance targets from the PRD:

| Metric | Target | Without Redis |
|---|---|---|
| Cache hit response | < 50ms p99 | ~10–25ms ✅ |
| Autocomplete | < 100ms p99 | ~15–30ms ✅ |
| Cache miss (AI) | < 5s p95 | Unchanged ✅ |

PostgreSQL with a primary-key index on `word_lower` returns a single row in
5–15ms. App Service to PostgreSQL round-trip on the Azure internal network adds
~2–5ms. Total: 10–25ms — well within the 50ms target.

Redis becomes necessary when:
- PostgreSQL CPU is sustained > 60% (many concurrent lookups of the same words)
- p99 for cached words drifts > 50ms under real load
- Daily active users exceed ~5,000

The app already handles Redis being absent gracefully — `CacheService` catches
connection failures and falls through to PostgreSQL silently. No code change is
needed to add Redis later.

---

## Why Removing Front Door CDN Is Safe for Beta

Front Door adds ~$35/month plus per-GB transfer cost. At beta scale, audio is
served directly from Azure Blob Storage over HTTPS. Blob Storage has its own CDN
edge in UAE North, so latency to regional users is already low (~20–50ms).

CDN becomes valuable when:
- Audio requests are in the thousands per day
- Users are geographically spread outside the UAE
- p99 audio load time is noticeably slow

---

## App Service Tier: B2 vs S1

The production Bicep uses S1 Standard (~$73/month):
- 1 vCore, 1.75 GB RAM
- Auto-scaling (up to 10 instances)
- Deployment slots

Beta uses B2 Basic (~$26/month):
- 2 vCores, 3.5 GB RAM — **more CPU and RAM than S1 for less money**
- No auto-scaling, no deployment slots
- Custom domains ✅, SSL ✅, Always On ✅

For a .NET 8 API with an in-process background batch processor (word queue), the
extra RAM on B2 is worth more than auto-scaling at this stage.

---

## Database Tier: Burstable B2s vs GeneralPurpose D2ds_v4

Production uses `Standard_D2ds_v4` (GeneralPurpose, 2 vCores, 8 GB RAM): ~$180/month.  
Beta uses `Standard_B2s` (Burstable, 2 vCores, 4 GB RAM): ~$37/month.

Burstable tier shares CPU with a baseline allocation (20% of 2 vCores = ~0.4 vCores
sustained) and bursts to full 2 vCores when needed. For a word lookup workload that
is read-heavy with short bursts, this is ideal.

Upgrade to GeneralPurpose when:
- Database CPU credit balance is consistently depleted (visible in Azure Monitor)
- Sustained queries require > 20% CPU continuously

---

## Deployment Instructions

### Prerequisites

- Azure CLI installed and logged in (`az login`)
- Resource group exists or create it:
  ```bash
  az group create --name lughatai-beta-rg --location uaenorth
  ```

### Deploy

```bash
az deployment group create \
  --resource-group lughatai-beta-rg \
  --template-file infrastructure/beta/main.bicep \
  --parameters infrastructure/beta/parameters.bicepparam \
  --parameters \
    dbAdminPassword="<strong-password>" \
    anthropicApiKey="sk-ant-..." \
    openAiApiKey="sk-..." \
    jwtSecret="<32-char-random-string>" \
    adminApiKey="<32-char-random-string>"
```

### Post-deploy checklist

1. **Run DB migrations** against the new PostgreSQL server:
   ```bash
   cd api
   dotnet ef database update --connection "<connection-string-from-deploy-output>"
   ```

2. **Restore word definitions** from backup:
   ```powershell
   .\scripts\db_restore.ps1
   ```

3. **Set env vars on Vercel** (frontend):
   - `NEXT_PUBLIC_API_URL` = `https://<app-service-hostname>`
   - `NEXT_PUBLIC_SITE_URL` = `https://urdumeaning.com`

4. **Point DNS** to App Service hostname.

5. **Smoke test** the 5 key paths:
   - `GET /health` → 200
   - `GET /api/word/mercy` → word JSON with Urdu
   - `GET /api/search?q=me` → autocomplete results
   - `GET /api/word-of-the-day` → word JSON
   - `GET /api/browse` → paginated list

---

## Scaling Triggers

Add each service back in this order as traffic grows:

| Signal | Action |
|---|---|
| PostgreSQL CPU credit balance < 20% sustained | Upgrade DB to GeneralPurpose D2ds_v4 |
| Word lookup p99 > 50ms under load | Add Redis (C0 Basic first, then C1 Standard) |
| App Service CPU > 70% sustained | Upgrade App Service to S1/S2 with auto-scale |
| Audio requests > 1,000/day | Add Front Door CDN in front of Blob Storage |
| Geography expands beyond UAE/South Asia | Add Front Door CDN for global edge |
| `BatchProcessor__Enabled=true` causing API slowness | Split batch processor to a separate App Service or Azure Container Job |

---

## Beta Limitations

- **No Redis** — word cache hits served from PostgreSQL (~10–25ms vs ~2ms with Redis).
  Not user-visible at beta traffic levels.
- **No CDN** — audio files served directly from Blob Storage. Slightly slower for
  users outside UAE. Acceptable for beta.
- **No auto-scaling** — B2 Basic has a single instance. If traffic spikes beyond
  ~50 concurrent users, upgrade to S1 with auto-scale.
- **Burstable DB CPU** — under sustained load (e.g. batch processor running + many
  live users), CPU credits can deplete. Monitor in Azure Portal.
- **Batch processor on same instance** — the word queue processor runs in-process
  on the API server. Disable `BatchProcessor__Enabled` after the initial word
  generation run to reclaim CPU for serving requests.

---

## Files

```
infrastructure/
  main.bicep                  ← Full production (do not modify)
  parameters.bicepparam       ← Full production params
  modules/                    ← Production modules (do not modify)
  beta/
    main.bicep                ← Beta orchestrator (3 services)
    parameters.bicepparam     ← Beta params
    modules/
      appservice.bicep        ← B2 Basic, no Redis, no CDN
      database.bicep          ← Burstable B2s
      speech.bicep            ← S0 pay-per-use (same as prod)
```

Storage module is shared: `infrastructure/beta/main.bicep` references
`../modules/storage.bicep` directly.
