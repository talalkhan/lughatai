# UrduMeaning — Agent Instructions

> Read this file first. Every agent (Claude Code, Codex, Antigravity, etc.) working on this
> project must read CLAUDE.md + PROJECT_PLAN.md before writing any code.

## What Is This

UrduMeaning is an AI-powered English-to-Urdu dictionary web app.
- Cache-first: AI called once per word, result stored forever in PostgreSQL.
- Owner: ThetaFoundry LLC
- PRD: stored at `docs/UrduMeaning_PRD_v1.2.docx` (canonical reference for all requirements)

---

## Repository Layout

```
lughatai/
├── CLAUDE.md                  ← You are here. Agent instructions.
├── PROJECT_PLAN.md            ← Living task tracker. Update after every task.
├── docs/
│   └── UrduMeaning_PRD_v1.2.docx ← Full PRD. Source of truth for all requirements.
├── api/                       ← ASP.NET Core 8 backend
│   ├── Controllers/
│   ├── Services/
│   ├── Models/
│   ├── Data/
│   ├── BackgroundJobs/
│   ├── Prompts/
│   │   └── ai_system_prompt.txt
│   ├── Program.cs
│   └── appsettings.json
├── web/                       ← Next.js 14 frontend
│   ├── app/
│   │   ├── page.tsx           ← Home (search + WOTD)
│   │   ├── word/[slug]/
│   │   │   └── page.tsx       ← Word detail (SSR)
│   │   ├── browse/
│   │   ├── flashcards/        ← Phase 2
│   │   ├── quiz/              ← Phase 2
│   │   ├── favorites/         ← Phase 2
│   │   ├── history/           ← Phase 2
│   │   └── auth/              ← Phase 2
│   ├── components/
│   │   ├── SearchBar.tsx
│   │   ├── WordCard.tsx
│   │   ├── AudioPlayer.tsx
│   │   └── ...
│   └── lib/
│       ├── api.ts             ← API client (typed fetch wrapper)
│       └── hooks/
├── scripts/
│   ├── seed_word_queue.sql        ← Loads 10k words into word_queue
│   ├── db_backup.ps1              ← Dump word_definitions → data/word_definitions_backup.sql
│   └── db_restore.ps1             ← Restore from that file into running Postgres
├── data/
│   └── word_definitions_backup.sql ← ⚠ CRITICAL: committed SQL backup of all AI-generated words
├── infrastructure/            ← Azure Bicep IaC (Phase 1 end)
└── docker-compose.yml         ← Local dev: Postgres on 5433, Redis on 6379
```

---

## Tech Stack (Locked)

| Layer | Technology | Version |
|-------|-----------|---------|
| Frontend | Next.js + React | 14 (App Router) |
| PWA | next-pwa (Workbox) | Phase 3 |
| Backend | ASP.NET Core | 8 |
| ORM | Dapper (queries) + EF Core (migrations) | latest |
| Database | PostgreSQL with JSONB | 16 |
| Cache | Redis | Azure Cache for Redis |
| AI Primary | Anthropic Claude | Haiku (batch), Sonnet (live miss) |
| AI Fallback | OpenAI | GPT-4o Mini |
| TTS | Azure Cognitive Speech | - |
| Storage | Azure Blob Storage | - |
| Cloud | Microsoft Azure | - |
| CI/CD | Azure DevOps Pipelines | - |
| Monitoring | Azure Application Insights + Datadog | App Insights active (beta); Datadog optional |
| Auth | ASP.NET Core Identity + JWT | Phase 2 |

---

## Environment Variables

Create `api/appsettings.Development.json` (never commit secrets):

```json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5433;Database=lughatai;Username=postgres;Password=postgres"
  },
  "Redis": {
    "Connection": "localhost:6379"
  },
  "AI": {
    "AnthropicApiKey": "YOUR_KEY",
    "OpenAIApiKey": "YOUR_KEY",
    "BatchModel": "claude-haiku-4-5",
    "LiveModel": "claude-sonnet-4-6"
  },
  "Azure": {
    "SpeechKey": "",
    "SpeechRegion": "",
    "BlobConnection": ""
  },
  "ApplicationInsights": {
    "ConnectionString": ""  // leave empty for local dev; set in Azure App Service config
  },
  "Jwt": {
    "Secret": "dev-secret-min-32-chars-long-here",
    "ExpiryHours": 1,
    "RefreshExpiryDays": 30
  },
  "Cors": {
    "AllowedOrigins": ["http://localhost:3000"]
  },
  "WordGeneration": {
    "Enabled": false,
    "RequireApprovedWord": true
  },
  "Enrichment": {
    "Enabled": true,
    "MaxPerHour": 30
  },
  "Notifications": {
    "Email": {
      "Enabled": true,                         // false in production appsettings.json; flip on per-env
      "SmtpHost": "smtp.gmail.com",
      "SmtpPort": 587,
      "SmtpUsername": "urdumeaningreport@gmail.com",
      "SmtpPassword": "GMAIL_APP_PASSWORD",    // 16-char App Password, NOT the account password
      "From": "urdumeaningreport@gmail.com",
      "To": "admin@thetafoundry.com",
      "SiteBaseUrl": "http://localhost:3000"   // production overrides to https://urdumeaning.com
    }
  }
}
```

Create `web/.env.local`:
```
NEXT_PUBLIC_API_URL=http://localhost:5000
NEXT_PUBLIC_SITE_URL=https://urdumeaning.com
NEXT_PUBLIC_GA_MEASUREMENT_ID=
NEXT_PUBLIC_PLAUSIBLE_DOMAIN=
GOOGLE_SITE_VERIFICATION=
BING_SITE_VERIFICATION=
```

---

## Local Dev Setup

```powershell
# 1. Start infrastructure (Postgres on port 5433, Redis on 6379)
docker compose up -d

# 2. Run DB migrations
cd api; dotnet ef database update

# 3. Seed word queue (optional — loads 10k words for batch processing)
docker compose exec -T postgres psql -U postgres -d lughatai -f /dev/stdin < scripts/seed_word_queue.sql

# 4. Start API
cd api; dotnet run

# 5. Start frontend
cd web; npm install; npm run dev
```

API runs on http://localhost:5000
Frontend runs on http://localhost:3000

> **Port note:** Docker Postgres is mapped to **5433** (not 5432) to avoid conflicts
> with a local Windows PostgreSQL service. The connection string in
> `appsettings.Development.json` must use `Port=5433`.

---

## Database Safety — Backup & Restore

`data/word_definitions_backup.sql` is a **committed SQL dump** of every
AI-generated word definition. It is your safety net. If Docker is wiped,
your laptop dies, or anything else goes wrong, this file plus git is all
you need to recover.

### After every generation session — back up and push

```powershell
.\scripts\db_backup.ps1
# prints the word count and the exact git commands to run:
git add data\word_definitions_backup.sql
git commit -m "backup: 847 words"
git push
```

### Full disaster recovery from scratch

```powershell
git pull                            # get latest backup from GitHub
docker compose up -d                # fresh containers
cd api; dotnet ef database update   # apply schema
cd ..; .\scripts\db_restore.ps1     # restore all words (~1 min for 10k)
# → "Restore complete: 847 words in database"
```

### Storage layers at a glance

| Layer | What's stored | Survives |
|-------|--------------|---------|
| GitHub `data/word_definitions_backup.sql` | All AI-generated definitions | Everything — laptop death, Docker wipe |
| Docker `pgdata` named volume | Same, live copy | `docker compose down` ✅  `docker compose down -v` ❌ |
| Redis | Hot cache only | Container restart ❌ (auto-refills from Postgres) |

### ⚠ Never run `docker compose down -v` unless you intend to wipe the DB

`-v` deletes named volumes including `pgdata`. Always back up first if you
need to do a full reset.

---

## Populating the Database with Quality Data

Word definitions are generated by Claude and stored permanently in `word_definitions`.
The batch processor (`WordQueueProcessor`) works through the `word_queue` table using
Haiku for bulk words and Sonnet for the most important ones.

### One-time setup (do this once)

**1. Add your Anthropic API key** to `api/appsettings.Development.json`:
```json
"AI": {
  "AnthropicApiKey": "sk-ant-...",
  "OpenAIApiKey":    "sk-...",
  "BatchModel":      "claude-haiku-4-5",
  "LiveModel":       "claude-sonnet-4-6"
}
```

**2. Seed the word queue** (10,000 common English words, priority-ranked):
```powershell
docker compose exec -T postgres psql -U postgres -d lughatai `
  -f /scripts/seed_word_queue.sql
# or from host:
Get-Content scripts/seed_word_queue.sql | docker compose exec -T postgres psql -U postgres -d lughatai
```

**3. Filter out stop words** (removes ~180 useless function words like "the", "be", "a"):
```powershell
Get-Content scripts/filter_stop_words.sql | docker compose exec -T postgres psql -U postgres -d lughatai
# → prints a table showing how many words remain per priority tier
```

**4. Enable the batch processor** in `api/appsettings.Development.json`:
```json
"BatchProcessor": {
  "Enabled": true
}
```

### Running the batch processor

Open two PowerShell terminals side by side:

**Terminal 1 — run the API (this is what generates the words):**
```powershell
cd api; dotnet run
# You will see log lines like:
# [INF] Processed 'knowledge' via sonnet
# [INF] Processed 'ability' via haiku
```

**Terminal 2 — watch progress:**
```powershell
.\scripts\monitor_queue.ps1
# Shows a live progress bar, words/min rate, ETA, and last 5 words generated
```

### Quality tiers (automatic)

| Priority | Words | Model | Quality | When |
|----------|-------|-------|---------|------|
| 1 | Top ~800 real words | **Claude Sonnet** | Rich — better poetry, examples, etymology | Processed first |
| 2 | Words 1001–5000 | Claude Haiku | Good — follows full schema | After P1 done |
| 3 | Words 5001–10000 | Claude Haiku | Good | After P2 done |

### Speed and cost (rough estimates)

| Stage | Words | Time | Notes |
|-------|-------|------|-------|
| Priority 1 (Sonnet) | ~800 | ~2–3 hrs | ~5 words/min, Sonnet is slower |
| Priority 2–3 (Haiku) | ~8,500 | ~2–3 hrs | ~50 words/min |
| **Total** | **~9,300** | **~5 hrs** | Run overnight |

### After the batch finishes

The monitor will print "Queue complete!" and tell you to back up:
```powershell
.\scripts\db_backup.ps1
git add data\word_definitions_backup.sql
git commit -m "backup: 9300 words"
git push
```

### Retrying failed words

If some words failed (API timeout, rate limit):
```powershell
# Via API:
Invoke-RestMethod -Method POST http://localhost:5000/api/admin/queue/retry-failed `
  -Headers @{ 'X-Admin-Key' = 'dev-admin-key-change-in-production' }
# Then restart the API — the processor will pick them up automatically
```

### On-demand (single words)

Any word a real user looks up that isn't in the DB is automatically generated
by Claude Sonnet and cached permanently. You don't need to pre-generate every word.

### Adding more words after the initial 10k

**From a text file** (one word per line, `#` lines are comments):
```powershell
# High-quality domains (Sonnet) — religious, emotional, literary vocabulary
.\scripts\add_words.ps1 -File scripts\words\islamic_religious.txt  -Priority 1
.\scripts\add_words.ps1 -File scripts\words\emotions_psychology.txt -Priority 1

# Bulk domains (Haiku) — academic, tech, professional
.\scripts\add_words.ps1 -File scripts\words\academic_formal.txt -Priority 2
.\scripts\add_words.ps1 -File scripts\words\technology.txt      -Priority 2

# Your own list — just make a .txt file and point at it
.\scripts\add_words.ps1 -File scripts\words\my_custom_list.txt -Priority 2
```

Words already in the queue or already defined are silently skipped — safe to run multiple times.
See `scripts/words/README.md` for the full list of curated domain files.

**Single word via API** (API must be running):
```powershell
Invoke-RestMethod -Method POST http://localhost:5000/api/admin/queue/add `
  -Headers @{ 'X-Admin-Key' = 'dev-admin-key-change-in-production'; 'Content-Type' = 'application/json' } `
  -Body '{ "words": ["ephemeral", "solitude"], "priority": 1 }'
```

---

## Architecture Decisions (Locked — Do Not Revisit)

These are final decisions from PRD Section 14. Do not change without explicit user instruction.

| # | Decision | Detail |
|---|----------|--------|
| 1 | App name | UrduMeaning |
| 2 | Roman Urdu search | String match against stored `roman_urdu` field only (Phase 1). AI-powered in Phase 2. |
| 3 | Audio generation | Lazy — generate on first play, cache forever in Azure Blob |
| 4 | Devanagari | Skip Phase 1 & 2. JSON field reserved. Populate in Phase 3. |
| 5 | Islamic references | Only include when AI finds genuine verifiable reference. Null otherwise. |
| 6 | Poetry attribution | AI-generated in Phase 1 with disclaimer. Verify in Phase 2. |
| 7 | Offline storage | PWA Service Worker + IndexedDB. Phase 3. |
| 8 | User corrections | Flag button only. Logs to `corrections` table. No free-text Phase 1. |
| 9 | Platform | Responsive web (Next.js) + PWA. No native app. |
| 10 | Monetization | Stripe Checkout (web-native). Phase 3. |

---

## ⚠ AI Cost Controls — Read Before Touching Anything AI-Related

These controls exist because search engine crawlers + misconfigured background jobs
drained $10+ in API credits with zero real user benefit. Do not revert them.

### Anthropic account status (as of 2026-05-27)

**The Anthropic account is at $0 balance.** Every call returns HTTP 400:
`"Your credit balance is too low to access the Anthropic API."`

Anthropic checks billing BEFORE validating the model name, so the model name validity
(`claude-sonnet-4-6`, `claude-haiku-4-5`) cannot be confirmed until credits are added.
To restore Claude: go to https://console.anthropic.com → Plans & Billing → add credits.

### Claude model names (correct as of 2026-05-27)

| Config key | Current Azure value | Notes |
|------------|---------------------|-------|
| `AI:BatchModel` | `gpt-4o-mini` | Used by WordEnrichmentProcessor and Roman Urdu fallback (when enabled) |
| `AI:LiveModel` | `gpt-4o-mini` | Used by WordService live generation (currently disabled in production) |

Claude returns HTTP 400 currently because Anthropic account has $0. Not confirmed invalid.
Code has a `gpt-*` shortcut: if BatchModel or LiveModel starts with "gpt-", AIService routes
directly to OpenAI with no Claude attempt. Roman Urdu interpretation also routes to OpenAI
when `AI__BatchModel` starts with `gpt-`.

**To verify model names:** add Anthropic credits, then set `WordGeneration__Enabled=true`
in Azure and watch App Insights Dependencies — 200 = model is valid, 400 = wrong name.

### BatchProcessor — must stay OFF in production

`BatchProcessor:Enabled` is `false` in `appsettings.json` and in all Bicep templates.
**Do not set it to `true` in Azure App Service config.** When enabled, it processes
the entire `word_queue` table using the live Claude API at full per-token prices —
not the discounted OpenAI Batch API. With 300k+ words pending, enabling it will
drain hundreds of dollars in hours. It was accidentally left `true` in Azure and
drained $10 overnight with no users on the site.

To bulk-generate words use: `scripts/batch_submit_openai.ps1` (50% discount, async).

### WordGeneration and Enrichment — both OFF by default in production

Two master on/off switches guard against bot-triggered AI spend:

| Config key | Default (appsettings.json) | Production (Azure) | What it controls |
|---|---|---|---|
| `WordGeneration:Enabled` | `false` | `false` | Live AI generation in `WordService` for single words not in DB |
| `WordGeneration:RequireApprovedWord` | `true` | `true` | Blocks live AI generation unless the missing word already exists in `approved_words` |
| `Enrichment:Enabled` | `false` | `false` | Background enrichment in `WordEnrichmentProcessor` |

**`WordGeneration:Enabled` is `false` in production as of 2026-05-27 night.**
Keep it off until live generation is intentionally re-enabled with active monitoring.
The code also blocks crawler-shaped slugs before generation: whitespace, encoded `%...`
URLs, `+`, hyphenated/non-alpha slugs, and any normalized value that is not a clean
single English token. This protects against crawlers hitting arbitrary `/word/...` pages
and turning SSR into AI spend.

Live generation also requires whitelist membership by default. Keep
`WordGeneration:RequireApprovedWord=true`; otherwise clean alphabetic crawler strings like
`producedunderfactorysupervision` can be sent to AI, hallucinated, and saved permanently.
`approved_words` is the durable validity table; `word_queue` is only batch processing state
and may be empty in production. Use `scripts/populate_approved_words_from_bulk.ps1` to
load the generated 340k-word list into `approved_words`, and use
`scripts/audit_unqueued_definitions.sql` plus `scripts/cleanup_unapproved_definitions.sql`
to inspect/quarantine existing bad generated rows before cleanup.

SEO crawl control: valid single-word `/word/...` pages can still be crawled at high
volume and force SSR to call `/api/word/{word}`. Because live generation is now guarded
by `WordGeneration:Enabled=false` in production plus `RequireApprovedWord=true`, the web
app may expose known word pages to search crawlers again, but only in a controlled way:
`robots.txt` allows `/word/` for general crawlers, `sitemap.xml` lists only existing
words returned by `/api/browse` and is capped by `SITEMAP_WORD_LIMIT` (default 1000), and
`web/middleware.ts` still blocks high-noise crawlers such as Ahrefs/Semrush/GPTBot while
allowing Googlebot/Bingbot/DuckDuckBot.

After reopening SEO, monitor Application Insights Dependencies for `api.openai.com` and
`api.anthropic.com`; these should remain at zero unless a deliberate generation/enrichment
run is enabled. Also monitor `/api/word/*` request volume and 404s before raising
`SITEMAP_WORD_LIMIT`.

**`WordGeneration:Enabled=false`** is an emergency kill switch — set it in Azure App
Service config (no deployment needed) to freeze new word generation if AI costs spike.

### WordEnrichmentProcessor — also rate-limited to 30/hour

Even when `Enrichment:Enabled=true`, the processor is capped at **30 enrichments per
hour** (configurable via `Enrichment:MaxPerHour`). Do not remove the cap. Here is why:

- The sitemap (`web/app/sitemap.ts`) lists up to 10,000 word URLs and revalidates hourly.
- Google/Bing crawl every URL in the sitemap — that is not real user traffic.
- Without the rate limit, each crawler page hit triggers an AI enrichment call.
- 600 crawler hits/hour × ~$0.001/call = $14/day with zero user benefit.

The rate limit means crawlers can index freely while AI spend stays bounded.

### WordEnrichmentProcessor — uses Haiku, not Sonnet

Background enrichment uses `usePremium: false` → `BatchModel` (Haiku).
Do not change it to `usePremium: true`. Haiku produces perfectly good enrichments
for background upgrades. Sonnet is reserved for live cache misses on brand-new words
that real users look up in real time.

### Roman Urdu search — uses Haiku, not Sonnet

`InterpretRomanUrduAsync` uses `BatchModel` (Haiku). It is a 50-token task.
Do not switch it back to `LiveModel` (Sonnet).

### Next.js word page — React cache() for deduplication

`web/app/word/[slug]/page.tsx` uses `React.cache()` to wrap `getWord()`.
Both `generateMetadata` and the page component call `getWordCached()`, not `getWord()`
directly. This ensures **one** API call per page render instead of two.
Do not remove the `cache()` wrapper or call `getWord()` directly in this file.

---

## Report Notifications (user "Report error" → admin email)

When a user clicks the flag button on a word page, the flow is:

1. `web/components/FlagButton.tsx` POSTs `{ reason, notes }` to `/api/word/{word}/flag`.
2. `WordController.FlagWord` is rate-limited (`"flag"` policy, 5/IP/hour) and validates input.
3. `WordRepository.AddCorrectionAsync` inserts into the `corrections` table **only if**
   the same `(word, reason, user)` is not already `open` within the last 24 hours.
   It returns `bool` — `true` = real new row inserted, `false` = duplicate skipped.
4. If `true`, the controller fires `IReportNotificationService.NotifyAsync(...)`
   **fire-and-forget**. The notifier sends an email via Gmail SMTP using
   `System.Net.Mail.SmtpClient` (no NuGet package — built into .NET).

### Why the design is the way it is — do not change without reading this

- **`AddCorrectionAsync` returns `bool` on purpose.** The bool tells the controller
  whether a real new row was inserted (vs. a 24h duplicate). The email only fires
  on `true`, so a single angry user spam-clicking the flag button cannot flood the
  admin inbox. Don't revert it to `Task` (void) — you'll break dedupe.
- **The email send is fire-and-forget (`_ = NotifyAsync(...)`).** Awaiting it
  would add Gmail latency to the user-facing flag endpoint and let SMTP failures
  surface as 500s. `NotifyAsync` is documented to never throw — keep it that way.
- **`Notifications:Email:Enabled` is `false` in `appsettings.json`.** Production
  flips it on via Azure App Service env vars. Keep the default off so a fresh
  environment without credentials doesn't log warnings on every report.
- **Gmail App Password, not the account password.** Generate at
  `https://myaccount.google.com/apppasswords` (requires 2FA). The 16-char password
  is shown with spaces — the service strips spaces before authenticating, so either
  format works in config.

### Production Azure env vars

Set on `lughatai-beta-api` App Service config:

```
Notifications__Email__Enabled       = true
Notifications__Email__SmtpHost      = smtp.gmail.com
Notifications__Email__SmtpPort      = 587
Notifications__Email__SmtpUsername  = urdumeaningreport@gmail.com
Notifications__Email__SmtpPassword  = <16-char Gmail App Password>
Notifications__Email__From          = urdumeaningreport@gmail.com
Notifications__Email__To            = admin@thetafoundry.com
```

`SiteBaseUrl` defaults to `https://urdumeaning.com` in `appsettings.json`.

### Rotating the password

To rotate the Gmail App Password (do this if it leaks or after every chat where it
was pasted in plain text):

1. https://myaccount.google.com/apppasswords → delete the `UrduMeaning API` entry
2. Create a new one named the same
3. Update `Notifications__Email__SmtpPassword` in Azure App Service config
4. Update local `api/appsettings.Development.json` (gitignored — safe)

### Limits

Gmail free-tier outbound: ~500 emails/day from a single account. At report volume
this is effectively infinite. If we ever exceed it, the SMTP send will throw,
`NotifyAsync` will log a warning, and the underlying `corrections` row is still
saved — admin sees reports via `GET /api/admin/corrections` even when email is
down.

---

## AI System Prompt

The exact system prompt for word generation is in `api/Prompts/ai_system_prompt.txt`.
**Never modify the prompt without updating that file.** The prompt instructs the AI to:
- Return ONLY valid JSON (no preamble, no markdown fences)
- All Urdu in Unicode Nastaliq script
- Include Roman Urdu for all translations
- Include multiple meanings if applicable
- Islamic/poetry refs only when genuinely applicable
- Follow the exact JSON schema in PRD Section 6

---

## Word JSON Schema

Every word stored follows the schema in PRD Section 6. Key top-level fields:
`word`, `phonetic`, `audio`, `learning`, `etymology`, `script_variants`,
`meanings[]`, `word_family`, `related_words`, `memory_tip`, `urdu_poetry`,
`urdu_proverb`, `islamic_reference`, `_meta`

The `meanings[]` array supports multiple parts of speech. Each meaning has:
`pos`, `definition_en`, `definition_ur`, `translations`, `synonyms`,
`antonyms`, `collocations`, `examples[]`, `confusables[]`

---

## API Endpoints Reference

| Method | Route | Auth | Phase |
|--------|-------|------|-------|
| GET | `/api/word/{word}` | None | 1 |
| GET | `/api/search?q=&limit=10` | None | 1 |
| GET | `/api/word-of-the-day` | None | 1 |
| GET | `/api/browse?context=&difficulty=&page=&limit=` | None | 1 |
| GET | `/api/word/random?difficulty=` | None | 1 |
| GET | `/api/user/favorites` | JWT | 2 |
| POST | `/api/user/favorites/{word}` | JWT | 2 |
| DELETE | `/api/user/favorites/{word}` | JWT | 2 |
| GET | `/api/user/history` | JWT | 2 |
| POST | `/api/auth/register` | None | 2 |
| POST | `/api/auth/login` | None | 2 |
| POST | `/api/auth/refresh` | None | 2 |
| GET | `/api/admin/queue/status` | Internal | 1 |
| POST | `/api/admin/queue/add` | Internal | 1 |
| POST | `/api/admin/queue/retry-failed` | Internal | 1 |

---

## Code Conventions

### Backend (C#)
- Use Dapper for all read queries (performance). EF Core for migrations only.
- All controller actions return `IActionResult` with typed responses.
- Services are injected via constructor DI. Register in `Program.cs`.
- Word normalization: `word.Trim().ToLowerInvariant()` before any DB query.
- JSONB deserialization: use `System.Text.Json` with `JsonSerializerOptions` set to camelCase.
- Never call AI API from controllers directly. Always go through `WordService`.
- Increment `lookup_count` on every cache hit AND miss.
- AI failures: log the error, return 503 with `{ error: "Service temporarily unavailable" }`.

### Frontend (TypeScript/Next.js)
- App Router only. No Pages Router.
- All word detail pages MUST be SSR (`async function` server components with `generateMetadata`).
- Urdu text: always wrap in `<span dir="rtl" lang="ur" className="font-nastaliq">`.
- Search bar: 300ms debounce on input. Min 2 chars before API call.
- Loading states: skeleton screens (not spinners alone).
- Error states: show friendly message + retry button.
- Touch targets: minimum 44×44px for all interactive elements.
- Dark mode: use `prefers-color-scheme` via Tailwind `dark:` variants.
- API calls: use the typed client in `lib/api.ts`, never raw fetch in components.
- Never hardcode `localhost:5000`. Always use `process.env.NEXT_PUBLIC_API_URL`.

### Both
- No TODO comments in committed code. Use PROJECT_PLAN.md for pending work.
- No console.log / Console.WriteLine in committed code.
- All secrets via environment variables. Never hardcode.

---

## Performance Targets (from PRD Section 11)

| Metric | Target |
|--------|--------|
| Cache hit response | < 50ms p99 |
| Cache miss (AI + save) | < 5s p95 |
| Autocomplete | < 100ms p99 |
| LCP (web) | < 2.5s |
| API uptime | 99.9% |

---

## How to Use PROJECT_PLAN.md

After completing any task:
1. Mark the task `[x]` in PROJECT_PLAN.md
2. Fill in the "Completed" date
3. Add any notes about implementation decisions or gotchas
4. If you hit a blocker, mark `[!]` and describe it in the Notes field
5. Update the "Current Status" section at the top

**Always commit PROJECT_PLAN.md changes with your code commits.**
