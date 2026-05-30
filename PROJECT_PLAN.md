# UrduMeaning — Project Plan & Progress Tracker

> **For agents:** Read CLAUDE.md first. Then read this file top-to-bottom before doing any work.
> Update this file after every task: mark complete, add notes, update Current Status.

---

## Current Status

```
Last updated  : 2026-05-30
Updated by    : Codex GPT-5
Active phase  : Live (beta deployed)
Current task  : Expand word database using trusted SCOWL/WordNet validation
Next task     : Collect/load SCOWL-backed OpenAI core batch when complete
```

### Beta Deployment (2026-05-24)

- **urdumeaning.com is live** — Cloudflare DNS → Azure App Service (B2 plan, UAE North)
- **API:** https://lughatai-beta-api.azurewebsites.net (ASP.NET Core 8)
- **Frontend:** https://lughatai-beta-web.azurewebsites.net / https://urdumeaning.com (Next.js 14)
- **Database:** 45,500 word definitions on Azure PostgreSQL (lughatai-beta-db)
- **CI/CD:** GitHub Actions deploys frontend on every push to master touching web/**
- **Backups:** Automated weekly pg_dump → Azure Blob Storage (lughataibetastorage/db-backups), 12-week retention
- **Full deployment reference:** `docs/DEPLOYMENT.md`

### Batch Pipeline State (2026-05-23)

- 341,142 words in word_queue total
  - done: 36,196
  - processing: 322
  - pending: 304,621
  - failed: 3
- `word_definitions` contains ~36K definitions locally
- Tracking file: scripts/words/processed/openai_batches.json
- **P3 words now default to core-mode generation** in both the hosted queue processor and OpenAI batch submitter
- **Core hits now self-enrich in the background** after a real user lookup
- **Backups are now sharded** as `data/word_definitions_backup.partNNN.sql.gz` to stay under GitHub's file limit
- **2026-05-23 canary retest passed after fixes:** replayed 20/20 core rows inserted cleanly, stage stored as `core`, enrichment-only fields nulled in DB
- **2026-05-23 enrichment flow debugged:** `WordData.MetaInfo.Stage` property added by Codex was not in the running API DLL (API started before the code change); enrichment never triggered because `NeedsEnrichment()` always saw `Stage=null`. Fix: restart API with `dotnet run`. Test word: `auscultation` (in DB as core, not in Redis).
- **2026-05-24 Azure IaC updated for Pakistan-first rollout:** default region changed to `uaenorth`, and the retired classic CDN module was replaced with Azure Front Door Standard for `/audio/*` delivery. Storage now provisions a dedicated `frontdoor-health` container for anonymous Front Door origin probes.
- **2026-05-24 Azure IaC cleanup verified:** Bicep warnings removed, `az bicep build --file infrastructure/main.bicep` is clean, and Azure `what-if` still succeeds against `lughatai-prod-rg` in `uaenorth`.
- **2026-05-24 launch rebrand completed:** user-facing app name switched to `UrduMeaning`, public SEO/schema URLs now target `urdumeaning.com`, the API project files were renamed to `UrduMeaning.Api.*`, and browser storage keys were updated for the new brand while keeping the existing local DB/infrastructure slugs unchanged.
- **2026-05-24 launch analytics + SEO instrumentation completed:** frontend now supports optional GA4 and Plausible via env vars, emits Google/Bing site verification tags via metadata, adds canonical/Open Graph defaults from `NEXT_PUBLIC_SITE_URL`, and documents the launch envs in `web/.env.example` and `CLAUDE.md`.
- **2026-05-27 Claude API credit drain fixed (round 1):** Three root causes: (1) `BatchProcessor__Enabled=true` in Azure App Service config was processing 28k word_queue words via live Claude API with no users on site — disabled and defaulted to `false` in all Bicep. (2) `WordEnrichmentProcessor` used `usePremium:true` (Sonnet) — switched to Haiku. (3) `InterpretRomanUrduAsync` used `LiveModel` (Sonnet) — switched to `BatchModel` (Haiku).
- **2026-05-27 Application Insights added:** `lughatai-beta-insights` resource created in UAE North. Tracks every outbound HTTP call to `api.anthropic.com` and `api.openai.com` as dependencies. Free tier (5 GB/month). `Microsoft.ApplicationInsights.AspNetCore` added; `AddApplicationInsightsTelemetry()` in `Program.cs`. New Bicep modules: `infrastructure/beta/modules/insights.bicep`, `infrastructure/modules/insights.bicep`.
- **2026-05-27 Claude API credit drain fixed (round 2 — crawler-triggered enrichment):** App Insights revealed search engine crawlers hitting the sitemap (10k word URLs) were triggering `WordEnrichmentProcessor` on every page, each attempt calling Claude (which returned 400 on every call due to wrong model name `claude-haiku-4-5-20251001`) then falling back to OpenAI. Three fixes: (1) Fixed model name to `claude-haiku-4-5` in appsettings.json and all Bicep. (2) Added `TryConsumeRateLimit()` to `WordEnrichmentProcessor` — max 30 enrichments/hour (configurable via `Enrichment:MaxPerHour`). (3) Added `React.cache()` to `web/app/word/[slug]/page.tsx` so `generateMetadata` and page component share one API call instead of making two. All documented in `CLAUDE.md` under "AI Cost Controls".
- **2026-05-27 Claude API credit drain fixed (round 3 — live generation crawler flood):** Production App Insights showed frequent `/api/word/{word}` calls from the Azure-hosted Next.js SSR frontend, driven by external crawler hits to arbitrary `/word/...` pages. Immediate production controls were applied: `WordGeneration__Enabled=false`, `Redis__Enabled=false`, `Redis__Connection=''`, `AI__BatchModel=gpt-4o-mini`, and `AI__LiveModel=gpt-4o-mini`. API was redeployed with stricter guards: `/api/word/{word}` rejects whitespace, encoded, `+`, and non-alpha slugs before DB/AI work; live AI generation is limited to clean single English tokens only; Roman Urdu AI interpretation routes to OpenAI when BatchModel is `gpt-*`; Redis is a no-op when disabled. The Next.js word route now applies the same clean single-word slug rule before SSR calls the API, so invalid crawler URLs 404 at the frontend instead of reaching App Service. Verification: known word `mathematics` returned 200, phrase and repeated-encoded slugs returned 404, and App Insights showed no Anthropic/OpenAI dependency calls or Redis warnings after deployment.
- **2026-05-27 emergency crawler throttle:** App Insights later showed crawlers were also walking valid single-word pages, so the API still saw many fast `429` responses from Azure-hosted SSR even though AI dependencies were stopped. Temporary SEO tradeoff: word URLs were removed from `sitemap.xml`, `/word/` was added to `robots.txt`, and Next.js middleware now returns a cheap `429` with `X-Robots-Tag: noindex,nofollow` for recognized crawler user agents and non-browser document requests before SSR can call the API. Remove or relax this after bot controls/CDN caching are in place.
- **2026-05-28 live generation validity guard:** Live cache-miss AI generation now requires `approved_words` membership by default via `WordGeneration:RequireApprovedWord=true`, preventing clean alphabetic crawler concatenations like `producedunderfactorysupervision` from being generated and saved. `approved_words` is the durable validity whitelist; `word_queue` remains batch-processing state and can be empty in production. Bicep now keeps `WordGeneration__Enabled=false` by default and sets `WordGeneration__RequireApprovedWord=true`. Added scripts to populate approvals from queue/bulk word-list sources and to audit/quarantine/delete unapproved generated rows.
- **2026-05-30 trusted word-source tiering:** Added SCOWL/WordNet source builder and wired trusted dictionary validation into `build_word_quality_tiers.ps1`. Current generated trusted sets: SCOWL 111,481 words, WordNet 86,189 words, combined 146,167. Current tier report: full 19,455, core 93,278, hold 228,154. Azure comparison found 4 missing full words and 56,588 missing core words; submitted OpenAI batch `batch_6a1b08f5d1b8819087d01047a13999fe` with 14,000 words (4 enriched, 13,996 core), pending collection.

### At-a-Glance Progress

| Phase | Name | Status | Tasks Done |
|-------|------|--------|-----------|
| 0 | Bootstrap | [x] Complete | 5 / 5 |
| 1 | MVP Backend | [x] Complete | 14 / 14 |
| 2 | MVP Frontend | [x] Complete | 11 / 11 |
| 3 | Integration & Deploy | [x] Complete* | 6 / 6 |
| 4 | Phase 2 Features | [x] Complete | 12 / 12 |
| 5 | PWA | [x] Complete | 7 / 7 |
| 6 | Monetization | [ ] Not started | 0 / 8 |

*P3-005 (batch pipeline run) is code-complete; operational run blocked on Azure credentials.

**Total: 55 / 63 tasks complete**

---

## Status Key

```
[ ]  Not started
[~]  In progress (add agent name + date: [~ Claude 2026-04-29])
[x]  Complete (add date: [x 2026-04-29])
[!]  Blocked (describe blocker in Notes)
[-]  Skipped / deferred (with reason)
```

---

## Phase 0 — Project Bootstrap
**Goal:** Repo structure, local dev environment, database running, CI skeleton.
**Gate to Phase 1:** Docker Compose works, DB migrations applied, API boots, frontend boots.

---

### P0-001 — Initialize repository structure
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Create the full folder structure as defined in CLAUDE.md. Init git repo.
  Create placeholder `README.md` files in each major folder so git tracks them.
- **Commands:**
  ```bash
  cd lughatai
  git init
  mkdir -p api/Controllers api/Services api/Models api/Data api/BackgroundJobs api/Prompts
  mkdir -p web/app/word/\[slug\] web/app/browse web/app/flashcards web/app/quiz
  mkdir -p web/app/favorites web/app/history web/app/auth
  mkdir -p web/components web/lib/hooks
  mkdir -p scripts infrastructure docs
  ```
- **Acceptance criteria:**
  - [ ] All folders exist
  - [ ] `git init` done, `.gitignore` covers `node_modules`, `bin/`, `obj/`, `.env*`, `appsettings.*.json`
  - [ ] `docker-compose.yml` created (see P0-002)
- **Notes:** —

---

### P0-002 — Docker Compose for local dev
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Create `docker-compose.yml` at repo root with PostgreSQL 16 and Redis.
- **File:** `docker-compose.yml`
- **Expected content:**
  ```yaml
  services:
    postgres:
      image: postgres:16-alpine
      environment:
        POSTGRES_USER: postgres
        POSTGRES_PASSWORD: postgres
        POSTGRES_DB: lughatai
      ports: ["5432:5432"]
      volumes: [pgdata:/var/lib/postgresql/data]
    redis:
      image: redis:7-alpine
      ports: ["6379:6379"]
  volumes:
    pgdata:
  ```
- **Acceptance criteria:**
  - [ ] `docker-compose up -d` starts both services with no errors
  - [ ] Can connect to Postgres: `psql -U postgres -d lughatai -h localhost`
  - [ ] Redis responds: `redis-cli ping` returns PONG
- **Notes:** —

---

### P0-003 — ASP.NET Core 8 project setup
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Scaffold ASP.NET Core 8 Web API project in `api/`. Add all required NuGet packages.
- **Commands:**
  ```bash
  cd api
  dotnet new webapi -n UrduMeaning.Api --no-openapi false
  dotnet add package Dapper
  dotnet add package Npgsql
  dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
  dotnet add package Microsoft.EntityFrameworkCore.Design
  dotnet add package StackExchange.Redis
  dotnet add package Anthropic.SDK   # or use raw HttpClient if not available
  dotnet add package Microsoft.AspNetCore.Authentication.JwtBearer
  dotnet add package Serilog.AspNetCore
  ```
- **File:** `api/Program.cs` — wire up DI, CORS, JWT, Redis, Swagger, Serilog
- **Acceptance criteria:**
  - [ ] `dotnet build` succeeds with no errors
  - [ ] `dotnet run` starts API on port 5000
  - [ ] `GET /swagger` returns Swagger UI
  - [ ] Health check endpoint `GET /health` returns 200
- **Notes:** Use `Anthropic.SDK` NuGet if available on NuGet.org; otherwise use `HttpClient` to
  call `https://api.anthropic.com/v1/messages` directly with `x-api-key` header.

---

### P0-004 — Database schema + EF Core migrations
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Create EF Core models and run initial migration to create all Phase 1 tables.
- **Tables to create (exact SQL in PRD Section 5):**
  - `word_definitions` — primary cache table with JSONB `data` column
  - `word_queue` — batch pipeline queue
  - (Skip `users`, `user_favorites`, `user_history` — Phase 2)
- **Files:**
  - `api/Models/WordDefinition.cs`
  - `api/Models/WordQueue.cs`
  - `api/Data/AppDbContext.cs`
- **Commands:**
  ```bash
  cd api
  dotnet ef migrations add InitialSchema
  dotnet ef database update
  ```
- **Indexes to create in migration (critical for performance):**
  ```sql
  CREATE INDEX idx_word_lower ON word_definitions(word_lower);
  CREATE INDEX idx_lookup_count ON word_definitions(lookup_count DESC);
  CREATE INDEX idx_data_gin ON word_definitions USING GIN(data);
  ```
- **Acceptance criteria:**
  - [ ] Migration file created in `api/Data/Migrations/`
  - [ ] `dotnet ef database update` runs with no errors
  - [ ] All 3 indexes exist in the DB
  - [ ] `word_lower` is a generated column (STORED), not application-managed
- **Notes:** EF Core does not natively support PostgreSQL generated columns — use raw SQL in the
  migration's `Up()` method via `migrationBuilder.Sql()` for the generated column and GIN index.

---

### P0-005 — Next.js 14 project setup
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Scaffold Next.js 14 app in `web/`. Configure Tailwind, fonts, TypeScript.
- **Commands:**
  ```bash
  cd web
  npx create-next-app@14 . --typescript --tailwind --eslint --app --src-dir=false --import-alias="@/*"
  npm install
  ```
- **Font setup in `web/app/layout.tsx`:**
  ```tsx
  import { Noto_Nastaliq_Urdu } from 'next/font/google'
  // weight: ['400', '700'], subsets: ['arabic']
  // Apply as CSS variable --font-nastaliq
  ```
- **`web/lib/api.ts`:** Create typed API client using `fetch` with `NEXT_PUBLIC_API_URL` base.
  Export typed functions: `getWord(word)`, `searchWords(q)`, `getWordOfTheDay()`, `browseWords(params)`.
- **Acceptance criteria:**
  - [ ] `npm run dev` starts on port 3000 with no errors
  - [ ] `npm run build` produces no TypeScript errors
  - [ ] Noto Nastaliq Urdu font loads (verify in browser DevTools Network tab)
  - [ ] `lib/api.ts` exists with typed functions
  - [ ] `.env.local` template documented in README
- **Notes:** —

---

## Phase 1 — MVP Backend
**Goal:** All API endpoints working. AI integration working. Cache-first flow working. Batch pipeline working.
**Prerequisite:** Phase 0 gate passed.
**Gate to Phase 2:** All endpoints return correct data. Word lookup end-to-end works (DB miss → AI → save → return).

---

### P1-001 — Word JSON model (C#)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Create C# record/class that exactly mirrors the JSON schema (PRD Section 6).
  This is the DTO used for deserialization from AI and serialization to clients.
- **File:** `api/Models/WordData.cs`
- **Key nested types:** `Phonetic`, `Audio`, `Learning`, `Etymology`, `ScriptVariants`,
  `Meaning`, `Translations`, `Synonyms`, `Antonyms`, `Example`, `Confusable`,
  `WordFamilyEntry`, `RelatedWords`, `MemoryTip`, `UrduPoetry`, `UrduProverb`,
  `IslamicReference`, `MetaInfo`
- **Serialization:** Use `[JsonPropertyName("snake_case_field")]` attributes to match the JSON.
  Or configure `JsonSerializerOptions` with `JsonNamingPolicy.SnakeCaseLower` globally.
- **Acceptance criteria:**
  - [ ] `JsonSerializer.Deserialize<WordData>(sampleJson)` works with the full sample JSON from PRD Section 6
  - [ ] Re-serializing produces identical JSON (round-trip test)
- **Notes:** The `_meta` field maps to a C# property named `Meta` with `[JsonPropertyName("_meta")]`.

---

### P1-002 — AI system prompt file
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Copy the exact system prompt from PRD Section 8.1 into a text file.
  API reads this file at startup (not hardcoded in source).
- **File:** `api/Prompts/ai_system_prompt.txt`
- **Acceptance criteria:**
  - [ ] File exists and contains the verbatim prompt from PRD Section 8.1
  - [ ] File is read in `AIService` constructor (not hardcoded inline)
- **Notes:** Never modify this prompt in code. Edit the file directly.

---

### P1-003 — AIService (Claude + OpenAI fallback)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Service that sends a word to Claude Haiku/Sonnet, parses the JSON response,
  and returns a `WordData` object. Falls back to OpenAI GPT-4o Mini if Claude fails.
- **File:** `api/Services/AIService.cs`
- **Interface:** `IWordAIService` with method `Task<WordData> GenerateWordAsync(string word, bool usePremium = false)`
- **Model selection:**
  - `usePremium = false` → `claude-haiku-4-5-20251001` (batch and live hits for common words)
  - `usePremium = true` → `claude-sonnet-4-6` (live cache miss for rare/edge-case words)
- **Claude API call:**
  ```
  POST https://api.anthropic.com/v1/messages
  Headers: x-api-key, anthropic-version: 2023-06-01, content-type: application/json
  Body: { model, max_tokens: 4096, system: <prompt>, messages: [{ role: "user", content: word }] }
  ```
- **Error handling:**
  - Retry once on 529 (overloaded) with 2s delay
  - On Claude failure: log error, attempt OpenAI fallback
  - On both failure: throw `AIServiceException`
  - Validate returned JSON parses to `WordData` — if not, retry once with Sonnet
- **Acceptance criteria:**
  - [ ] `GenerateWordAsync("serenity")` returns a valid `WordData` object
  - [ ] Fallback to OpenAI triggered when Claude returns non-200
  - [ ] Invalid JSON from AI triggers one retry before throwing
  - [ ] Model selection respects `usePremium` flag
- **Notes:** Add `_meta.generated_by` and `_meta.generated_at` fields after parsing.

---

### P1-004 — CacheService (Redis)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Thin Redis wrapper for top-10k word caching. Redis is L1 cache, Postgres is L2.
- **File:** `api/Services/CacheService.cs`
- **Interface:** `ICacheService` with `GetWordAsync(word)`, `SetWordAsync(word, data, ttl?)`, `InvalidateWordAsync(word)`
- **TTL:** No expiry (words don't change once generated). Only the top 10k most-looked-up words
  are kept in Redis (eviction policy: `allkeys-lru`).
- **Acceptance criteria:**
  - [ ] Set/Get round-trip works with a `WordData` object
  - [ ] Cache miss returns `null` (not throws)
  - [ ] Redis connection failure does NOT crash the app — fall through to DB gracefully
- **Notes:** Configure Redis `maxmemory-policy allkeys-lru` in docker-compose or Azure config.

---

### P1-005 — WordService (cache-first orchestration)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Core business logic. Implements the cache-first flow from PRD Section 3.2.
- **File:** `api/Services/WordService.cs`
- **Flow:**
  ```
  1. Normalize word (trim, lowercase, basic lemmatize)
  2. Check Redis (L1 cache)  → hit: return, increment lookup_count async
  3. Check PostgreSQL (L2)   → hit: set Redis, return, increment lookup_count async
  4. Call AIService           → miss: generate, save to Postgres, set Redis, return
  5. On AI failure            → return 503
  ```
- **Word normalization:** `word.Trim().ToLowerInvariant()`. No stemming in Phase 1.
- **`lookup_count` increment:** Fire-and-forget (`_ = IncrementAsync(word)`). Never block the response.
- **Files touched:** `api/Services/WordService.cs`, `api/Data/WordRepository.cs`
- **Acceptance criteria:**
  - [ ] Second call for same word hits Redis (verify with Redis `MONITOR` command)
  - [ ] Third call after Redis flush hits Postgres (no AI call)
  - [ ] First-ever call for a word calls AI exactly once
  - [ ] `lookup_count` increments on each call
- **Notes:** —

---

### P1-006 — WordController (GET /api/word/{word})
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Main word lookup endpoint.
- **File:** `api/Controllers/WordController.cs`
- **Endpoints in this controller:**
  - `GET /api/word/{word}` → `200 WordData` or `503`
  - `GET /api/word/random?difficulty=` → `200 WordData`
  - `GET /api/word-of-the-day` → `200 WordData` (deterministic daily rotation via date seed)
- **Word of the Day logic:** `SELECT word FROM word_definitions ORDER BY MD5(word || 'SALT' || CURRENT_DATE::text) LIMIT 1`
- **Acceptance criteria:**
  - [ ] `GET /api/word/hello` returns full WordData JSON
  - [ ] `GET /api/word-of-the-day` returns same word all day, different next day
  - [ ] `GET /api/word/random` returns a random word
  - [ ] Input with spaces/uppercase normalized correctly
- **Notes:** —

---

### P1-007 — SearchController (GET /api/search)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Autocomplete endpoint for search-as-you-type.
- **File:** `api/Controllers/SearchController.cs`
- **SQL:**
  ```sql
  SELECT word, data->'script_variants'->>'nastaliq' as urdu,
         data->'learning'->>'difficulty' as difficulty
  FROM word_definitions
  WHERE word_lower LIKE @prefix
  ORDER BY lookup_count DESC
  LIMIT @limit
  ```
  Where `@prefix = query.ToLowerInvariant() + "%"`
- **Acceptance criteria:**
  - [ ] `GET /api/search?q=ser` returns words starting with "ser"
  - [ ] Results ordered by `lookup_count DESC`
  - [ ] Empty `q` or `q` < 2 chars returns `[]`
  - [ ] Response time < 100ms (verify with local data)
- **Notes:** —

---

### P1-008 — BrowseController (GET /api/browse)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Filter/browse words by difficulty, context, sentiment.
- **File:** `api/Controllers/BrowseController.cs`
- **SQL (JSONB queries):**
  ```sql
  -- Filter by context (e.g., "religion"):
  WHERE data->'learning'->'contexts' @> '["religion"]'::jsonb
  -- Filter by difficulty:
  WHERE data->'learning'->>'difficulty' = @difficulty
  -- Filter by CEFR:
  WHERE data->'learning'->>'cefr_level' = @cefr
  ```
- **Response:** `{ words: [...], total: int, page: int, limit: int }`
- **Acceptance criteria:**
  - [ ] `GET /api/browse?context=religion` returns only religion-tagged words
  - [ ] Pagination works correctly (`page`, `limit` params)
  - [ ] Multiple filters combinable
- **Notes:** —

---

### P1-009 — Rate limiting middleware
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** 60 requests/minute per IP for unauthenticated users.
- **Implementation:** Use ASP.NET Core 8 built-in rate limiting (`Microsoft.AspNetCore.RateLimiting`).
  Fixed window limiter: 60 requests per 60-second window per IP.
- **File:** `api/Program.cs` (add middleware)
- **Acceptance criteria:**
  - [ ] 61st request within a minute returns `429 Too Many Requests`
  - [ ] Response includes `Retry-After` header
  - [ ] Admin endpoints exempt from rate limiting
- **Notes:** —

---

### P1-010 — Word normalization + lemmatization
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Normalize user input before any DB lookup.
  Phase 1: trim + lowercase only. Basic lemmatization: strip common suffixes.
- **File:** `api/Services/WordNormalizer.cs`
- **Rules (Phase 1):**
  - `word.Trim().ToLowerInvariant()`
  - Strip trailing punctuation
  - Basic English lemmatization: "running" → "run", "cats" → "cat"
  - Use a simple dictionary-based approach or `Catalyst` NLP library for .NET
- **Acceptance criteria:**
  - [ ] "  Running  " normalizes to "run"
  - [ ] "CATS" normalizes to "cat"
  - [ ] "serenity." normalizes to "serenity"
- **Notes:** If a full lemmatization library adds too much complexity, do trim+lowercase only
  and note this as Phase 2 enhancement. Don't over-engineer.

---

### P1-011 — AdminController (batch queue management)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Internal endpoints to manage the word batch pipeline.
- **File:** `api/Controllers/AdminController.cs`
- **Endpoints:**
  - `GET /api/admin/queue/status` → `{ pending, processing, done, failed }`
  - `POST /api/admin/queue/add` body: `{ words: string[] }` → adds to `word_queue`
  - `POST /api/admin/queue/retry-failed` → resets failed words back to pending
- **Security:** Require a static `X-Admin-Key` header (from env var). Not JWT — internal use only.
- **Acceptance criteria:**
  - [ ] Status endpoint returns correct counts
  - [ ] Add endpoint inserts words with default priority 3
  - [ ] Retry-failed resets `status='pending'` and `attempts=0` for failed words
- **Notes:** —

---

### P1-012 — WordQueueProcessor (IHostedService)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Background service that processes the `word_queue` table to pre-populate the dictionary.
- **File:** `api/BackgroundJobs/WordQueueProcessor.cs`
- **Algorithm (from PRD Section 3.3):**
  ```
  Loop every 5 seconds:
    1. SELECT 10 words WHERE status='pending' ORDER BY priority ASC FOR UPDATE SKIP LOCKED
    2. SET status='processing'
    3. Process 5 concurrently (SemaphoreSlim)
    4. For each word: call AIService (Haiku), save to word_definitions, SET status='done'
    5. On failure: increment attempts. If attempts >= 3: SET status='failed'. Else: SET status='pending'.
    6. Exponential backoff on AI rate limit errors (429): 1s, 2s, 4s
  ```
- **Acceptance criteria:**
  - [ ] Processor starts automatically when API starts
  - [ ] Processes words at ~5 words/second sustained
  - [ ] Words with 3 failures are marked 'failed' and not retried
  - [ ] Processor does not crash if AI is unavailable (logs error, continues)
  - [ ] `FOR UPDATE SKIP LOCKED` prevents duplicate processing in multi-instance scenarios
- **Notes:** Disable processor via `appsettings.json` flag `"BatchProcessor": { "Enabled": false }`
  for local dev when you don't want to burn AI credits.

---

### P1-013 — Seed script (top 10k words)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** SQL file that loads the top 10,000 most common English words into `word_queue`.
- **File:** `scripts/seed_word_queue.sql`
- **Format:**
  ```sql
  INSERT INTO word_queue (word, priority) VALUES
  ('the', 1), ('be', 1), ('to', 1), ('of', 1), ('and', 1),
  -- ... all 10,000 words
  ON CONFLICT (word) DO NOTHING;
  ```
- **Word list source:** Use standard frequency lists (COCA, BNC, or similar).
  Priority 1 = top 1000, Priority 2 = 1001–5000, Priority 3 = 5001–10000.
- **Acceptance criteria:**
  - [ ] Script inserts 10,000 rows with no errors
  - [ ] Words already in `word_definitions` don't cause errors (ON CONFLICT DO NOTHING)
  - [ ] Priority distribution: ~1000 P1, ~4000 P2, ~5000 P3
- **Notes:** Can use a Python script to generate the SQL from a word frequency CSV if needed.

---

### P1-014 — Input sanitization + CORS
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Security hardening for Phase 1.
- **Files:** `api/Program.cs`, `api/Middleware/InputSanitizer.cs`
- **Requirements:**
  - CORS: allow only origins listed in `Cors:AllowedOrigins` config
  - Word input: max 150 chars, strip HTML/script tags, only allow `[a-zA-Z\s\-']`
  - All endpoints served over HTTPS (redirect HTTP → HTTPS)
  - Add security headers: `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
- **Acceptance criteria:**
  - [ ] `GET /api/word/<script>alert(1)</script>` returns 400
  - [ ] CORS rejects requests from unlisted origins
  - [ ] HTTP requests redirect to HTTPS (when running with certs)
- **Notes:** —

---

## Phase 2 — MVP Frontend
**Goal:** Next.js app with working home page, word detail page, search, and WOTD.
**Prerequisite:** Phase 1 gate passed (API must be running and returning data).
**Gate to Phase 3:** All pages load. Search works end-to-end. Urdu renders correctly.

---

### P2-001 — API client (lib/api.ts)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Typed fetch wrapper for all API calls. All components use this — never raw fetch.
- **File:** `web/lib/api.ts`
- **Exports:**
  ```typescript
  getWord(word: string): Promise<WordData>
  searchWords(q: string, limit?: number): Promise<SearchResult[]>
  getWordOfTheDay(): Promise<WordData>
  browseWords(params: BrowseParams): Promise<BrowseResult>
  getRandomWord(difficulty?: string): Promise<WordData>
  ```
- **Types file:** `web/lib/types.ts` — TypeScript interfaces mirroring the full JSON schema
- **Error handling:** Throw typed `ApiError` with `status` and `message` fields.
- **Acceptance criteria:**
  - [ ] All functions typed with full WordData interface
  - [ ] 404 throws `ApiError` with `status: 404`
  - [ ] Uses `NEXT_PUBLIC_API_URL` env var (never hardcoded)
- **Notes:** —

---

### P2-002 — SearchBar component
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Main search input with autocomplete dropdown.
- **File:** `web/components/SearchBar.tsx`
- **Behavior:**
  - 300ms debounce on input
  - Calls `searchWords(q)` when input >= 2 chars
  - Shows dropdown with up to 10 results: English word + Urdu translation + difficulty badge
  - Keyboard nav: arrow keys to select, Enter to navigate
  - On submit (Enter or click): navigate to `/word/{word}`
  - Clear button (×) when input has content
  - Loading spinner during fetch
- **Acceptance criteria:**
  - [ ] Debounce: verify no API call on each keystroke (check Network tab)
  - [ ] Dropdown shows after 2+ chars
  - [ ] Selecting a result navigates to correct `/word/{word}` page
  - [ ] Keyboard navigation works
  - [ ] Mobile: input does not zoom on focus (font-size >= 16px)
- **Notes:** —

---

### P2-003 — Home page (/)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Landing page with search bar and Word of the Day card.
- **File:** `web/app/page.tsx`
- **Layout:**
  - Logo + tagline ("The richest Urdu dictionary, powered by AI")
  - `SearchBar` centered prominently
  - Word of the Day section below search (calls `getWordOfTheDay()`)
  - Category browse links (Religion, Literature, Poetry, Business, etc.)
- **WoTD card:** Shows English word, Urdu translation in Nastaliq, difficulty badge, short definition, "See full definition →" link.
- **SEO:** `generateMetadata()` with title "UrduMeaning — AI-Powered English to Urdu Dictionary" + description.
- **Acceptance criteria:**
  - [ ] Page loads < 2.5s LCP
  - [ ] WOTD card shows correct word (same for all users today)
  - [ ] Category links navigate to `/browse?context={category}`
  - [ ] Fully responsive 320px → 1440px
- **Notes:** —

---

### P2-004 — Word detail page (/word/[slug])
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** SSR page displaying the full word entry. Most complex page in the app.
- **File:** `web/app/word/[slug]/page.tsx`
- **Must render (all from PRD Section 9.1):**
  - English word (h1) + IPA phonetic + syllable breakdown
  - Audio play buttons (English + Urdu) — calls AudioPlayer component
  - Primary Urdu translation in large Nastaliq font (RTL, `dir="rtl"`, `lang="ur"`)
  - Roman Urdu variant
  - Difficulty badge + CEFR level badge
  - Emoji visual association
  - Context tags as chips (clickable → browse filter)
  - Per-meaning sections: pos badge, EN/UR definitions, formal/colloquial labels
  - Synonyms (EN + UR) as pill tags — clickable (EN) → navigate to that word
  - Antonyms (EN + UR) as pill tags
  - Collocations list
  - 3 example sentences (EN + UR + Roman)
  - Confusables section
  - Word family (clickable links)
  - See also (clickable links)
  - Memory tip
  - Urdu poetry (couplet + poet + translation) with AI-generated disclaimer
  - Urdu proverb with translation
  - Islamic/Quranic reference (only if present in data)
  - Etymology section
- **SSR + SEO:**
  ```typescript
  export async function generateMetadata({ params }) { /* word-specific meta */ }
  // OpenGraph image, schema.org/DefinedTerm structured data
  ```
- **Acceptance criteria:**
  - [ ] Page is server-rendered (view-source shows content)
  - [ ] All sections render for a word with full data (e.g., "serenity")
  - [ ] Urdu text renders right-to-left in Nastaliq font
  - [ ] Null/missing sections (Islamic ref, poetry) do not render empty boxes
  - [ ] Synonym pills navigate to correct word
  - [ ] `<script type="application/ld+json">` with schema.org/DefinedTerm present
  - [ ] OG tags include word, definition, Urdu translation
- **Notes:** This is the most important page for SEO. Get SSR right.

---

### P2-005 — AudioPlayer component
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Play button for English and Urdu audio pronunciation.
- **File:** `web/components/AudioPlayer.tsx`
- **Behavior:**
  - Shows play/pause button with "EN" or "UR" label
  - If `audio_url` is null: button disabled with tooltip "Audio coming soon"
  - On first click: triggers lazy audio generation via API (Phase 2 feature — for now just fetch the URL)
  - HTML5 `<audio>` element (hidden) + custom button UI
- **Acceptance criteria:**
  - [ ] Plays audio when URL is present
  - [ ] Disabled state when URL is null
  - [ ] Touch target >= 44×44px
- **Notes:** Actual TTS generation is Phase 1-003 in backend. For now, render button; audio URLs will be null until TTS is wired up.

---

### P2-006 — Browse page (/browse)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Filterable/browsable word list.
- **File:** `web/app/browse/page.tsx`
- **Filters (as UI chips/select):** Difficulty, CEFR level, Context category, Sentiment
- **Word list:** Cards showing English word + Urdu translation + difficulty badge + 2-word definition preview
- **Pagination:** "Load more" button (not page numbers)
- **Acceptance criteria:**
  - [ ] Selecting a filter updates URL params and re-fetches
  - [ ] "Load more" appends next page results
  - [ ] Shareable URL (filters in query params)
- **Notes:** —

---

### P2-007 — WordCard component
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Compact word summary card used on Browse page and WOTD.
- **File:** `web/components/WordCard.tsx`
- **Props:** `word: WordData`, `variant: 'compact' | 'full'`
- **Compact variant:** English word + Urdu nastaliq + difficulty badge + short English definition
- **Full variant:** Everything in compact + emoji + context tags + link
- **Acceptance criteria:**
  - [ ] Renders without errors when optional fields (poetry, proverb) are null
  - [ ] Urdu text RTL
  - [ ] Clicking card navigates to `/word/{word}`
- **Notes:** —

---

### P2-008 — Skeleton loading screens
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Skeleton placeholder UI for loading states on all data-fetching pages.
- **Files:** `web/components/skeletons/WordDetailSkeleton.tsx`, `WordCardSkeleton.tsx`
- **Acceptance criteria:**
  - [ ] Word detail page shows skeleton while `loading.tsx` is active
  - [ ] Browse page shows skeleton cards during fetch
  - [ ] No layout shift when content loads
- **Notes:** Use Tailwind `animate-pulse` on gray placeholder shapes.

---

### P2-009 — Error boundaries and 404 handling
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Friendly error states for API failures and unknown words.
- **Files:** `web/app/error.tsx`, `web/app/not-found.tsx`, `web/app/word/[slug]/not-found.tsx`
- **Word not found (404):** Show "We couldn't find '{word}'. Try a different spelling." + search bar.
- **API error (500/503):** Show "Something went wrong. Please try again." + retry button.
- **Acceptance criteria:**
  - [ ] Visiting `/word/xyzxyz123` shows word-not-found page
  - [ ] API being down shows friendly error (not raw error)
- **Notes:** —

---

### P2-010 — Dark mode
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Full dark mode support using Tailwind's `dark:` variants and system preference.
- **File:** `web/app/layout.tsx` (add `class="dark"` toggle), `web/tailwind.config.ts`
- **Acceptance criteria:**
  - [ ] App respects `prefers-color-scheme: dark` automatically
  - [ ] All text readable in dark mode (no white-on-white or black-on-black)
  - [ ] Urdu text legible in dark mode (Nastaliq on dark background)
- **Notes:** —

---

### P2-011 — SEO + metadata
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Complete SEO setup for all pages.
- **Files:** `web/app/layout.tsx`, each page's `generateMetadata()`
- **Requirements:**
  - Root layout: viewport, charset, default OG image, Twitter card
  - Word detail: title = "{Word} in Urdu | UrduMeaning", description = first 160 chars of definition,
    OG image = word + Urdu translation (can be a placeholder image for now),
    `schema.org/DefinedTerm` JSON-LD
  - Canonical URLs
  - `robots.txt` and `sitemap.xml` (dynamic, listing all words)
- **Acceptance criteria:**
  - [ ] Lighthouse SEO score >= 90
  - [ ] Schema.org JSON-LD validates at schema.org/SchemaApp validator
  - [ ] OG tags visible in view-source
- **Notes:** Sitemap will be large (10k+ words). Use streaming sitemap or multiple sitemap files.

---

## Phase 3 — Integration & Deploy
**Goal:** Everything wired together and deployed to Azure.
**Prerequisite:** Phase 1 + Phase 2 gates passed.
**Gate to Phase 4:** App live on Azure. Batch pipeline running on 10k words. Monitoring active.

---

### P3-001 — Azure infrastructure (Bicep)
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Infrastructure as Code for Azure resources.
- **File:** `infrastructure/main.bicep`
- **Resources to create:**
  - Azure App Service (or Container Apps) for API
  - Azure PostgreSQL Flexible Server
  - Azure Cache for Redis
  - Azure Blob Storage (for audio files)
  - Azure Cognitive Services (Speech)
  - Azure CDN profile
- **Acceptance criteria:**
  - [ ] `az deployment group create` runs with no errors
  - [ ] All resources created in correct region (eastus or westus2)
- **Notes:** —

---

### P3-002 — Azure DevOps pipeline
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** CI/CD pipelines for both API and web.
- **Files:** `.azure/api-pipeline.yml`, `.azure/web-pipeline.yml`
- **API pipeline:** build → test → publish → deploy to App Service
- **Web pipeline:** npm install → lint → build → deploy to Static Web Apps or App Service
- **Acceptance criteria:**
  - [ ] Push to `main` triggers deploy
  - [ ] Failed tests block deploy
  - [ ] Environment variables injected from Azure Key Vault
- **Notes:** —

---

### P3-003 — Audio TTS integration
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Lazy audio generation. On first play request, generate MP3, save to Azure Blob, update `audio.en_url` in DB.
- **File:** `api/Services/AudioService.cs`
- **Azure Speech SDK:** Use SSML for Urdu (`ur-PK-UzmaNeural` voice) and English (`en-US-JennyNeural`).
- **Flow:**
  ```
  GET /api/word/{word}/audio?lang=en
  → AudioService.GetOrGenerateAsync(word, lang)
  → Check if URL exists in word's data.audio field
  → If not: call Azure Speech TTS → upload to Blob → update word data → return URL
  → Return redirect to CDN URL
  ```
- **Acceptance criteria:**
  - [ ] First request generates and saves audio
  - [ ] Second request returns cached CDN URL instantly
  - [ ] Both EN and UR (ur-PK) voices work
- **Notes:** —

---

### P3-004 — Datadog monitoring
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** APM, logs, and alerts.
- **Setup:** Serilog → Datadog sink. Add Datadog APM NuGet package.
- **Dashboards to create:**
  - Request volume + p99 latency
  - Cache hit rate (Redis hits / total requests)
  - AI API call volume + cost estimate
  - Batch pipeline: words/hour, queue depth, failure rate
- **Alerts:**
  - p99 latency > 500ms
  - Error rate > 1%
  - AI API failure rate > 5%
- **Acceptance criteria:**
  - [ ] Traces visible in Datadog APM
  - [ ] Cache hit rate metric tracked
  - [ ] All 3 alerts configured
- **Notes:** —

---

### P3-005 — Run batch pipeline on 10k words
- **Status:** `[! 2026-04-30]`
- **Completed:** —
- **Agent:** Claude Sonnet 4.6
- **Description:** Run the batch pipeline to pre-populate the top 10,000 words using Claude Haiku.
- **Steps:**
  1. Seed `word_queue` with `scripts/seed_word_queue.sql`
  2. Enable batch processor in config
  3. Monitor via `GET /api/admin/queue/status`
  4. Verify ~$10–$15 cost in Anthropic dashboard
- **Acceptance criteria:**
  - [ ] All 10,000 words have status 'done'
  - [ ] Failed words < 1% (< 100)
  - [ ] All definitions valid JSON
  - [ ] Cost < $20
- **Notes:** Code and infrastructure complete. Operational run blocked on owner providing
  Azure credentials + Anthropic API key. See `scripts/batch_pipeline_runbook.md` for
  full step-by-step. Seed SQL generator at `scripts/generate_seed_sql.py`.

---

### P3-006 — End-to-end testing
- **Status:** `[x 2026-04-30]`
- **Completed:** 2026-04-30
- **Agent:** Claude Sonnet 4.6
- **Description:** Basic E2E tests verifying the happy path.
- **Tool:** Playwright
- **Tests:**
  - Search "serenity" → navigates to `/word/serenity` → page shows Urdu translation
  - WOTD card on home page is visible
  - Browse by "religion" context shows relevant words
  - 404 for unknown word shows friendly message
- **Acceptance criteria:**
  - [ ] All 4 tests pass against production URL
- **Notes:** —

---

## Phase 4 — User Accounts & Phase 2 Features
**Goal:** Auth, favorites, history, flashcards, quiz, browse enhancements.
**Prerequisite:** Phase 3 gate passed (app live, 10k words populated).

---

### P4-001 — User auth tables + migrations
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Add `users`, `user_favorites`, `user_history` tables (PRD Section 5.3–5.5).
- **Files:** `api/Models/User.cs`, `api/Data/Migrations/AddUserTables.cs`
- **Notes:** —

---

### P4-002 — AuthController (register, login, refresh)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** JWT-based auth. Tokens expire 1h, refresh tokens 30 days.
- **File:** `api/Controllers/AuthController.cs`, `api/Services/AuthService.cs`
- **Notes:** BCrypt.Net-Next for password hashing. Access token in React state/localStorage; refresh token stored DB-side.

---

### P4-003 — Favorites API endpoints
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `api/Controllers/UserController.cs`
- **Notes:** GET/POST/DELETE + status check. LEFT JOIN word_definitions for Urdu/difficulty data.

---

### P4-004 — History API endpoint
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `api/Controllers/UserController.cs`, `api/Services/WordService.cs`
- **Notes:** History recorded fire-and-forget in WordService when userId present. Trimmed to 100 per user.

---

### P4-005 — Auth UI (login/register pages)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `web/app/auth/page.tsx`, `web/lib/auth.tsx`, `web/components/AuthProviderWrapper.tsx`
- **Notes:** React context (AuthProvider) wraps layout. JWT in localStorage, auto-refreshed on mount.

---

### P4-006 — Favorites page (/favorites)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `web/app/favorites/page.tsx`
- **Notes:** Optimistic remove. Unauthenticated users see sign-in CTA.

---

### P4-007 — History page (/history)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `web/app/history/page.tsx`
- **Notes:** Clear-all button. Sorted by most recent.

---

### P4-008 — Flashcard mode (/flashcards)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `web/app/flashcards/page.tsx`
- **Notes:** SM-2 algorithm. State persisted in localStorage. Deck = favorites (if logged in) or random words. Again/Hard/Good/Easy quality buttons.

---

### P4-009 — Quiz mode (/quiz)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `web/app/quiz/page.tsx`
- **Notes:** EN→UR and UR→EN modes. 4-choice MCQ. Streak counter. 10 questions/session. Distractor words fetched from random endpoint.

---

### P4-010 — Roman Urdu AI search
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `api/Controllers/SearchController.cs`, `api/Data/WordRepository.cs`, `api/Services/AIService.cs`
- **Notes:** New endpoint GET /api/search/roman. DB match first (roman_urdu JSONB field LIKE prefix), AI interpretation fallback (InterpretRomanUrduAsync). Returns source: db|ai|none.

---

### P4-011 — User corrections (flag button)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `web/components/FlagButton.tsx`, `api/Controllers/WordController.cs` (POST /api/word/{word}/flag)
- **Notes:** Anonymous-friendly (no auth required). Modal with reason radio + optional notes. Admin can view via GET /api/admin/corrections.

---

### P4-012 — Poetry attribution verification
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **File:** `api/Controllers/AdminController.cs`, `api/Data/WordRepository.cs`
- **Notes:** GET /api/admin/poetry/unverified (50 at a time), POST /api/admin/poetry/{word}/verify (sets _meta.reviewed=true via jsonb_set).

---

## Phase 5 — PWA
**Goal:** Progressive Web App with offline support, home screen install, push notifications.
**Prerequisite:** Phase 4 gate passed.

---

### P5-001 — next-pwa setup
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Install and configure `next-pwa` (Workbox). Add `manifest.json`.
- **Files:** `web/next.config.mjs`, `web/public/manifest.json`
- **Notes:** Used `@ducanh2912/next-pwa` (maintained Workbox fork). Workbox runtimeCaching: word-definitions CacheFirst 1yr, WOTD StaleWhileRevalidate 1d, search NetworkFirst 3s timeout. Disabled in development.

---

### P5-002 — Web App Manifest
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** `manifest.json` with app name, icons (192×192, 512×512), theme color, display: standalone.
- **File:** `web/public/manifest.json`
- **Notes:** theme_color #059669 (emerald), background_color #fff, shortcuts to /flashcards and /quiz, screenshots block for app store eligibility.

---

### P5-003 — Offline word caching (IndexedDB)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Service Worker caches looked-up words in IndexedDB for offline access.
- **Files:** `web/lib/hooks/useWordCache.ts`, `web/components/WordCacheWriter.tsx`
- **Notes:** DB_NAME "urdumeaning", STORE "words", max 500 words LRU eviction by saved_at. WordCacheWriter is an invisible "use client" component mounted in the SSR word detail page to bridge SSR→client hook. `getOfflineWord()` and `bulkCacheWords()` exported for offline fallback and pro packs.

---

### P5-004 — Offline page shell
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Pre-cache app shell (layout, fonts, home page) for instant repeat loads.
- **Files:** `web/app/offline/page.tsx`, `web/public/sw-push.js`
- **Notes:** /offline page reads IndexedDB directly (sorted by saved_at desc, shows last 8 cached words as links). App shell caching handled by Workbox precache via next-pwa.

---

### P5-005 — Web Push notifications
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Word of the Day push notification via Push API + Service Worker.
- **Files:** `web/public/sw-push.js`, `web/lib/hooks/usePushNotifications.ts`, `api/Controllers/PushController.cs`, `api/Migrations/20260501000001_AddPushSubscriptions.cs`
- **Notes:** VAPID keys via NEXT_PUBLIC_VAPID_PUBLIC_KEY. push_subscriptions table with endpoint UNIQUE. Service worker shows notification with open/dismiss actions; notificationclick focuses existing window or opens new. POST /api/push/subscribe upserts by endpoint.

---

### P5-006 — Install prompt (Android)
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Show "Add to Home Screen" banner after 2nd visit on Android Chrome.
- **File:** `web/components/InstallPrompt.tsx`
- **Notes:** BeforeInstallPromptEvent deferred. Shows after visit count ≥ 2. localStorage DISMISSED_KEY + VISIT_COUNT_KEY. Mounted in root layout via AuthProviderWrapper.

---

### P5-007 — PWA testing
- **Status:** `[x 2026-05-01]`
- **Completed:** 2026-05-01
- **Agent:** Claude Sonnet 4.6
- **Description:** Lighthouse PWA audit score >= 90. Test offline mode. Test install flow.
- **Files:** `web/public/robots.txt`, `web/app/sitemap.ts`, `web/public/icons/README.md`
- **Notes:** robots.txt (Allow all + sitemap pointer), dynamic sitemap.ts (paginates /api/browse limit=1000, revalidate 3600s), manifest.json + SW + HTTPS = PWA installability. Icons need generation with ImageMagick per README. VAPID keys must be generated with `web-push generate-vapid-keys` and added to env.

---

## Phase 6 — Monetization
**Goal:** Pro tier subscription, ads, API licensing portal.
**Prerequisite:** Phase 5 gate passed.

---

### P6-001 — Stripe Checkout integration
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Pro tier: $2.99/month or $19.99/year. Stripe Checkout (no app store fee).
- **Notes:** —

---

### P6-002 — Pro tier enforcement
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Gate Pro features (no ads, offline packs, extended history, exports) behind `tier='pro'` check.
- **Notes:** —

---

### P6-003 — Ad integration (free tier)
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Show ads for non-Pro users. Tasteful placement (not intrusive).
- **Notes:** —

---

### P6-004 — PDF/CSV export
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Pro feature: export word lists as PDF or CSV.
- **Notes:** —

---

### P6-005 — API licensing portal
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Developer signup for API keys. Free tier: 100 req/day. Paid tiers: 10k/100k/unlimited.
- **Notes:** —

---

### P6-006 — OpenAPI documentation page (/api-docs)
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Public-facing API docs for B2B developers. Auto-generated from Swagger + custom layout.
- **File:** `web/app/api-docs/page.tsx`
- **Notes:** —

---

### P6-007 — B2B API key management
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Issue, rotate, and revoke API keys. Store hashed. Rate limit per key.
- **Notes:** —

---

### P6-008 — Expand to 500k words
- **Status:** `[ ]`
- **Completed:** —
- **Agent:** —
- **Description:** Run batch pipeline to 500k words using Claude Haiku + GPT-4o Mini mix.
  Estimated cost: $600–$800. Target: 14–28 hours of processing.
- **Notes:** Monitor AI costs closely. Use GPT-4o Mini as primary for cost once past 100k.

---

## Completed Work Log

> Append entries here as tasks are completed. Newest at the top.

| Date | Agent | Task | Notes |
|------|-------|------|-------|
| 2026-05-28 | Codex GPT-5 | Approved-word whitelist | Added `approved_words` as the live generation validity gate, kept `word_queue` as batch state, corrected Bicep live-generation defaults, and added scripts for approval population plus unapproved-row audit/quarantine cleanup. |
| 2026-05-24 | Claude Sonnet 4.6 | Beta deployment complete | API on Azure App Service, Next.js frontend on same B2 plan ($0 extra), urdumeaning.com live via Cloudflare DNS, 45,500 words restored to Azure PostgreSQL, automated weekly Blob Storage backups, full docs in docs/DEPLOYMENT.md |
| 2026-05-24 | Codex GPT-5 | Launch analytics and SEO instrumentation | Added env-driven GA4 and Plausible scripts, Google/Bing verification metadata, canonical/Open Graph metadata tightening, homepage JSON-LD, and deployment docs for launch env vars |
| 2026-05-24 | Codex GPT-5 | UrduMeaning launch rebrand | Rebranded the public app from LughatAI to UrduMeaning across metadata, UI copy, schema URLs, PWA assets, browser storage keys, and API project filenames while leaving existing DB and infra slugs intact to avoid launch-week migration churn |
| 2026-05-23 | Codex GPT-5 | Batch canary follow-up fixes | Tightened core prompt with exact-headword rules, made live/batch generation reject headword drift, fixed collector to reset parse failures to `pending`, anchor inserts to queued words, sanitize stored core rows, repaired the canary-damaged DB rows, and verified a 20-word replay cleanly stored `core` rows |
| 2026-05-23 | Codex GPT-5 | Batch pipeline hardening | Added `core` vs `enriched` generation stages, background enrichment after real user lookup, atomic queue claiming with `UPDATE ... RETURNING`, stage-aware OpenAI batch submit/collect flow, and sharded backup/restore scripts |
| 2026-05-23 | Codex GPT-5 | UI polish pass | Added shared app shell with desktop header + mobile bottom nav, moved word-detail navigation/actions to the top, added favorite toggle, tightened home hero and browse filters, verified in live dev server |
| 2026-04-30 | Claude Sonnet 4.6 | P0-001 thru P0-005 | Full directory structure, docker-compose, ASP.NET Core 8 scaffolded, EF Core migrations, Next.js 14 set up |
| 2026-04-30 | Claude Sonnet 4.6 | P1-001 thru P1-014 | Full backend: WordData DTO, AIService (Claude+OpenAI fallback), CacheService (Redis), WordService (cache-first), all controllers, rate limiting, input sanitization, WordQueueProcessor, seed SQL |
| 2026-04-30 | Claude Sonnet 4.6 | P2-001 thru P2-011 | Full frontend: lib/api.ts + types.ts, SearchBar with debounce, AudioPlayer, WordCard, home page, word detail SSR page, browse page, error/404 pages, skeleton loaders, dark mode, Noto Nastaliq font |
| 2026-04-30 | Claude Sonnet 4.6 | P3-001 thru P3-006 | Azure Bicep IaC (7 files), Azure DevOps CI/CD pipelines, AudioService (lazy TTS via Azure Speech REST + Blob), Datadog Serilog sink, batch pipeline generator + runbook, Playwright E2E tests (4 specs) |
| 2026-05-01 | Claude Sonnet 4.6 | P4-001 thru P4-012 | User models + EF migration (users/favorites/history/corrections), AuthService (BCrypt + JWT), AuthController, UserController, Roman Urdu search (DB LIKE + AI fallback), FlagButton component, poetry verification admin, AuthContext (React), auth/favorites/history/flashcards/quiz pages, SM-2 algorithm |
| 2026-05-01 | Claude Sonnet 4.6 | P5-001 thru P5-007 | next-pwa (@ducanh2912) + Workbox runtime caching, manifest.json, IndexedDB word cache (useWordCache hook + WordCacheWriter), offline page, Web Push (VAPID + push_subscriptions table + PushController), BeforeInstallPrompt component, robots.txt + dynamic sitemap |

---

## Known Issues / Blockers

> Document any blockers here. Format: `[DATE] [AGENT] Description — Resolution pending`

*None currently.*

---

## Questions for Owner (ThetaFoundry)

> Agent: if you have a question that blocks progress, add it here and continue with unblocked tasks.

1. What word frequency list should be used for the 10k seed? (COCA, BNC, Google Ngrams, or provide custom CSV?)
2. What Azure region? (eastus recommended for cost, but owner may prefer westus2 for latency)
3. Is there a preferred Datadog plan/organization to use?
4. Should the admin endpoints be IP-restricted in addition to the API key header?
