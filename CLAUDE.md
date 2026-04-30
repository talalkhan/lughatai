# LughatAI — Agent Instructions

> Read this file first. Every agent (Claude Code, Codex, Antigravity, etc.) working on this
> project must read CLAUDE.md + PROJECT_PLAN.md before writing any code.

## What Is This

LughatAI is an AI-powered English-to-Urdu dictionary web app.
- Cache-first: AI called once per word, result stored forever in PostgreSQL.
- Owner: ThetaFoundry LLC
- PRD: stored at `docs/LughatAI_PRD_v1.2.md` (canonical reference for all requirements)

---

## Repository Layout

```
lughatai/
├── CLAUDE.md                  ← You are here. Agent instructions.
├── PROJECT_PLAN.md            ← Living task tracker. Update after every task.
├── docs/
│   └── LughatAI_PRD_v1.2.md  ← Full PRD. Source of truth for all requirements.
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
│   ├── seed_word_queue.sql    ← Loads 10k words into word_queue
│   └── export_definitions.sql
├── infrastructure/            ← Azure Bicep IaC (Phase 1 end)
└── docker-compose.yml         ← Local dev: Postgres + Redis
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
| Monitoring | Datadog | - |
| Auth | ASP.NET Core Identity + JWT | Phase 2 |

---

## Environment Variables

Create `api/appsettings.Development.json` (never commit secrets):

```json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5432;Database=lughatai;Username=postgres;Password=postgres"
  },
  "Redis": {
    "Connection": "localhost:6379"
  },
  "AI": {
    "AnthropicApiKey": "YOUR_KEY",
    "OpenAIApiKey": "YOUR_KEY",
    "BatchModel": "claude-haiku-4-5-20251001",
    "LiveModel": "claude-sonnet-4-6"
  },
  "Azure": {
    "SpeechKey": "",
    "SpeechRegion": "",
    "BlobConnection": ""
  },
  "Jwt": {
    "Secret": "dev-secret-min-32-chars-long-here",
    "ExpiryHours": 1,
    "RefreshExpiryDays": 30
  },
  "Cors": {
    "AllowedOrigins": ["http://localhost:3000"]
  }
}
```

Create `web/.env.local`:
```
NEXT_PUBLIC_API_URL=http://localhost:5000
```

---

## Local Dev Setup

```bash
# 1. Start infrastructure
docker-compose up -d

# 2. Run DB migrations
cd api && dotnet ef database update

# 3. Seed word queue (after migrations)
psql -U postgres -d lughatai -f scripts/seed_word_queue.sql

# 4. Start API
cd api && dotnet run

# 5. Start frontend
cd web && npm install && npm run dev
```

API runs on http://localhost:5000
Frontend runs on http://localhost:3000

---

## Architecture Decisions (Locked — Do Not Revisit)

These are final decisions from PRD Section 14. Do not change without explicit user instruction.

| # | Decision | Detail |
|---|----------|--------|
| 1 | App name | LughatAI |
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
