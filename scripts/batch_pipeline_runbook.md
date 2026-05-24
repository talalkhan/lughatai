# UrduMeaning — Batch Pipeline Runbook (P3-005)

Pre-requisites before running this runbook:
- Azure resources deployed (P3-001 complete, `az deployment group create` succeeded)
- Anthropic API key added to appsettings.Development.json or Azure App Settings
- API builds and passes `GET /health` check

---

## Step 1 — Expand the seed SQL (if needed)

The checked-in `seed_word_queue.sql` contains ~500 representative words for local dev.
For a full 10k seed, generate a larger SQL file:

```bash
cd scripts
python generate_seed_sql.py > seed_word_queue_full.sql
```

Review the output, then load it:

```bash
# Local
psql -U postgres -d lughatai -f scripts/seed_word_queue_full.sql

# Azure (get connection string from Azure Portal → PostgreSQL → Connection strings)
psql "host=<server>.postgres.database.azure.com user=lughatadmin dbname=lughatai sslmode=require" \
  -f scripts/seed_word_queue_full.sql
```

---

## Step 2 — Enable the batch processor

**Local dev** (`api/appsettings.Development.json`):
```json
{
  "BatchProcessor": { "Enabled": true },
  "AI": { "AnthropicApiKey": "sk-ant-..." }
}
```

**Azure** — set via App Settings in Azure Portal or:
```bash
az webapp config appsettings set \
  --resource-group lughatai-prod-rg \
  --name lughatai-prod-api \
  --settings BatchProcessor__Enabled=true
```

---

## Step 3 — Monitor progress

Poll queue status every 30 seconds:

```bash
watch -n 30 'curl -s http://localhost:5000/api/admin/queue/status \
  -H "X-Admin-Key: your-admin-key" | jq .'
```

Expected output:
```json
{ "pending": 9500, "processing": 10, "done": 490, "failed": 0 }
```

Processing rate: ~5 words/second = ~10k words in ~33 minutes.

---

## Step 4 — Retry failed words

If any words land in `failed` status (typically AI parsing errors):

```bash
curl -X POST http://localhost:5000/api/admin/queue/retry-failed \
  -H "X-Admin-Key: your-admin-key"
```

Acceptable failure rate: < 1% (< 100 words out of 10k).

---

## Step 5 — Verify completion

```bash
curl -s http://localhost:5000/api/admin/queue/status \
  -H "X-Admin-Key: your-admin-key"
# Expected: { "pending": 0, "processing": 0, "done": 10000, "failed": < 100 }

# Spot-check a definition
curl -s http://localhost:5000/api/word/serenity | jq '.meanings[0].definition_en'
```

---

## Cost Estimate

| Model | Words | Tokens/word (est.) | Cost/1M tokens | Total |
|-------|-------|-------------------|---------------|-------|
| claude-haiku-4-5 | 10,000 | ~800 input + ~1200 output | $0.25 / $1.25 | ~$17 |

Expected cost: **$10–20** for 10k words. Stay under $25.

Check usage: Anthropic Console → Usage → filter by date.

---

## Disable after completion

```bash
az webapp config appsettings set \
  --resource-group lughatai-prod-rg \
  --name lughatai-prod-api \
  --settings BatchProcessor__Enabled=false
```
