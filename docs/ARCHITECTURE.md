# Architecture Reference

How the app works end to end. Verified against code at commit `9793df4` (2026-11-01). If you change behaviour described here, update this file in the same commit.

## System Overview

```
Browser / PWA ──► Next.js 14 (web/, Azure App Service, SSR)
                       │  lib/api.ts (typed fetch, NEXT_PUBLIC_API_URL)
                       ▼
                 ASP.NET Core 8 API (api/, Azure App Service)
                       │
        ┌──────────────┼───────────────┬──────────────┐
        ▼              ▼               ▼              ▼
   Redis (L1,      PostgreSQL 16    AI providers    Azure Speech +
   OFF in prod)    (L2, JSONB)      (OpenAI/Claude) Blob (audio, lazy)
```

DNS/CDN: Cloudflare -> Azure (UAE North). Azure Front Door serves `/audio/*` (Bicep). Monitoring: Application Insights (Datadog sink optional).

## Request flow: GET /api/word/{word}

1. `WordController.GetWord` rejects slugs that are not `^[a-zA-Z]+$` (no `%`, `+`, whitespace) -> 404. Length > 150 -> 400.
2. `WordService.GetWordAsync` normalizes (`WordNormalizer`), then: Redis (if enabled) -> Postgres `word_definitions` -> live AI generation.
3. Live generation runs only if ALL hold: clean `^[a-z]+$` token, `WordGeneration:Enabled=true`, and (`RequireApprovedWord`) word is in `approved_words`. Production has it OFF, so a miss = 404.
4. Cache hits/misses increment `lookup_count`. Authenticated users get history recorded (fire-and-forget).
5. If the stored row is stage `core` (not `enriched`), `WordEnrichmentProcessor` is queued (only when `Enrichment:Enabled`, max 30/hour).

Frontend `web/app/word/[slug]/page.tsx` is SSR; `getWord` is wrapped in `React.cache()` so metadata + page share one API call. `web/middleware.ts` guards `/word/*`: 404 for bad paths, 429 for noisy crawlers and non-browser requests, allows Googlebot/Bingbot/DuckDuckBot/Yandex/Baidu/Applebot and real browsers.

## Backend map (`api/`)

| Area | Files | Notes |
|---|---|---|
| Controllers | `WordController`, `SearchController` (`/search`, `/search/roman`), `BrowseController`, `UserController` (JWT: favorites/history/me), `AuthController` (register/login/refresh/logout), `PushController`, `AdminController` (X-Admin-Key: queue, corrections, poetry verification) | All under `RequireRateLimiting("ip")`; extra policies `flag`, `auth`, `ai-search`, `admin` |
| Services | `WordService` (orchestration), `AIService` (OpenAI/Claude, prompts from `Prompts/`), `CacheService`, `AudioService` (lazy TTS to Blob), `AuthService`, `WordNormalizer`, `ReportNotificationService` (Gmail SMTP) | |
| Data | `AppDbContext` (EF, migrations only), `WordRepository` (Dapper reads/writes) | |
| Background | `WordQueueProcessor` (BatchProcessor; keep OFF), `WordEnrichmentProcessor` (core -> enriched; rate-limited) | |
| Middleware | `InputSanitizerMiddleware` | |
| Tables | `word_definitions`, `approved_words`, `word_queue`, `users`, `user_favorites`, `user_history`, `corrections` (+ `definition_snapshot`), `push_subscriptions` | 7 migrations in `api/Migrations/` |

Word entry stages (`_meta.stage`): `core` (minimal, bulk-generated) vs `enriched` (full: etymology, poetry, collocations...). Models recorded per row in `word_definitions.model`.

## Frontend map (`web/`)

Routes: `/` (search + word of the day), `/word/[slug]` (SSR), `/browse`, `/favorites`, `/history`, `/flashcards` (SM-2), `/quiz`, `/auth`, `/offline`, `/about`, `/contact`, `/privacy`, `/terms`, plus `robots.ts` and `sitemap.ts` (existing words only, capped by `SITEMAP_WORD_LIMIT`, default 1000). PWA via next-pwa + IndexedDB word cache + web push. E2E: Playwright in `web/e2e/`.

## Deploy & CI

- `.github/workflows/deploy-api.yml` / `deploy-web.yml`: push to `master` touching `api/**` or `web/**` -> deploy to Azure App Service (`lughatai-beta-api`, `lughatai-beta-web`).
- `.github/workflows/backup-db.yml`: weekly pg_dump to Blob (`lughataibetastorage/db-backups`).
- `.github/workflows/docs-freshness.yml`: PRs that change code must also touch `docs/STATUS.md`.
- IaC in `infrastructure/` (Bicep). Details in DEPLOYMENT.md. Merging to master deploys to production.

## Data pipeline (scripts/)

`scripts/*.ps1` are PowerShell (Windows-first). Groups: batch generation via OpenAI Batch (`batch_submit_openai`, `batch_collect_openai`), word sourcing/tiers (`build_trusted_word_sources`, `build_word_quality_tiers`, `populate_approved_words_from_bulk`), Azure audit/repair (`audit_azure_*`, `quarantine_azure_*`, `repair_azure_*`, `load_semantic_*`), backup/restore (`db_backup`, `db_restore*`). See OPERATIONS.md and `scripts/*.md` runbooks. Running these needs production credentials that agents usually do not have.

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

## Performance Targets (from PRD Section 11)

| Metric | Target |
|--------|--------|
| Cache hit response | < 50ms p99 |
| Cache miss (AI + save) | < 5s p95 |
| Autocomplete | < 100ms p99 |
| LCP (web) | < 2.5s |
| API uptime | 99.9% |

---
