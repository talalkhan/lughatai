# UrduMeaning — Current Status

> **The first thing to read after AGENTS.md.** Keep it short and true. Update at the end of every session.
> Items marked *(as of DATE)* come from docs/people, not from a live check — the repo cannot see Azure. Re-verify before quoting them as fact.

```
Last updated : 2026-11-01
Updated by   : Claude (live Azure verification session)
Repo head    : master @ 9793df4 (2026-06-03) — no code commits since; the gap to today is ~5 months
Phase        : LIVE (beta) at urdumeaning.com
```

## One-paragraph summary

UrduMeaning is live in beta. English-to-Urdu entries are AI-generated once and served from Postgres. Core product (search, word pages, browse, WOTD, accounts, favorites/history, flashcards, quiz, PWA/offline, push, audio, report-an-error) is built and deployed. **Live AI generation is ON in production by design** (`WordGeneration__Enabled=true`): any approved word is generated on cache miss regardless of whether a real user or a crawler/bot triggers it — `RequireApprovedWord` is the actual safety gate, not the `Enabled` switch (owner-confirmed policy, 2026-11-01; see `docs/COST_CONTROLS.md`). The dictionary is served from ~186k definitions (184k pre-generated + organic growth from live misses). The last work was data-quality repair and a controlled reopening of SEO crawling. Monetization (Stripe) has not started.

## Production snapshot *(live-verified 2026-11-01 via `az` CLI against resource group `lughatai-beta-rg`, tenant `726691ab-a6db-46f6-a9a1-8514ac57401e`, sub `8e1196e3-...-1189854`)*

| Item | Value | vs. docs |
|---|---|---|
| Definitions in Azure Postgres | **186,110** (verified via public `/api/browse` `total` field) | docs said 184,072 (2026-06-03) — grown ~2k, consistent with live generation being on |
| `WordGeneration__Enabled` | **`true`** | Intentional per owner-confirmed policy 2026-11-01 (see below) — previously documented as a hard kill switch that "must stay false"; that doc language is now stale, fixed in `docs/COST_CONTROLS.md` |
| `WordGeneration__RequireApprovedWord` | `true` | matches — this is the real safety gate, not the `Enabled` switch |
| `BatchProcessor__Enabled` | `false` | matches |
| `Enrichment__Enabled` | `false` (`MaxPerHour=0`) | matches (fully frozen, even stricter than the documented 30/hr cap) |
| `Redis__Enabled` | `false` | matches |
| `AI__BatchModel` / `AI__LiveModel` | `gpt-4o-mini` / `gpt-4o-mini` | matches |
| `RomanSearchAI__Enabled` | not set in Azure App Settings (code default `false` applies) | effectively matches, but bicep's explicit `false` isn't actually deployed as an app setting — silent reliance on code default |
| `Notifications__Email__Enabled` | `true` | matches |
| Web: `NEXT_PUBLIC_API_URL` | `https://lughatai-beta-api.azurewebsites.net` | matches |
| Web: `SITEMAP_WORD_LIMIT` | not set in Azure App Settings (code default `1000` applies) | matches effectively |
| App Insights — `api.openai.com` dependency calls since 2026-06-03 | **774 calls**, first at 2026-08-04, last at 2026-11-01 (today) | Expected under current policy — live generation firing for ~3 months, correlated with a crawl-traffic spike starting 2026-08-31. Previously this doc said it must stay zero; that was wrong, see below |
| App Insights — `api.anthropic.com` dependency calls, ever | **0** | matches (Anthropic path still unused) |
| `/api/word/{word}` traffic since 2026-06-03 | 705,483× 200, 57,309× 404, 81,318× 429 (bot-blocked), 4,905× 500, 174× 503 | New data — this volume/404 check was flagged in docs as never having been done |
| Hosting | Azure UAE North, B2 plan, Cloudflare DNS; weekly DB backup to Blob (12-week retention) | unchanged, not re-verified this session |
| Report emails | Gmail SMTP to admin; `Notifications__Email__Enabled=true` in Azure | matches |

### ✅ Resolved 2026-11-01: `WordGeneration__Enabled=true` is intentional policy, not drift

When this was first discovered live-verified as `true` in production, it contradicted the old CLAUDE.md language calling it an "emergency kill switch" that must stay `false`. Owner reviewed and confirmed the real policy: generate any approved word on cache miss no matter who/what triggers the lookup (real user or crawler/bot) — `WordGeneration:RequireApprovedWord=true` is the actual safety control, not the `Enabled` switch. 774 `api.openai.com` calls since 2026-08-04 (rising with a crawl-traffic spike starting 2026-08-31) are expected behavior under this policy, on cheap `gpt-4o-mini` calls gated by the approved-words whitelist. Docs updated: `docs/COST_CONTROLS.md`, `docs/DECISIONS.md` (#11), `AGENTS.md` guardrail #1.

### ⚠️ Secrets were displayed in this session

The `az webapp config appsettings list` commands used to verify the above returned full plaintext values (Admin API key, Anthropic key, OpenAI key, Jwt secret, Blob account key, Speech key, Gmail SMTP app password, Postgres connection string). They were not deliberately echoed to the user, but appeared in raw tool output. Per the existing guidance in `docs/OPERATIONS.md`, treat these as exposed and consider rotating, especially the Gmail SMTP app password and Admin API key.

## What is done

Build phases 0–5 complete (backend, frontend, deploy, accounts, PWA). Cost-control hardening after three credit-drain incidents (2026-05-27). Trusted-word bulk generation via OpenAI Batch (SCOWL+WordNet list, 0 trusted words missing). Report feedback with definition snapshots. Details: `docs/HISTORY.md`.

## In flight / open

1. **SEO reopening monitoring — checked 2026-11-01, working as intended.** `api.openai.com` dependency calls are not zero (774 since 2026-08-04) — expected, since `WordGeneration__Enabled=true` is now documented policy, not a leak. `/api/word/*` volume is heavy (up to 155k/week) with thousands of 404s/week since the 2026-08-31 crawl spike. Still worth deciding whether to raise `SITEMAP_WORD_LIMIT` based on that volume.
2. **Semantic repair of Urdu translations** — paused. ~4.3k heuristic "assistant-like" rows remain; classified as review/defer, not confirmed bad. No safe automated bulk fix (see HISTORY 2026-06-02). Don't auto-regenerate.
3. **Monetization (build Phase 6)** — not started (0/8). An unmerged branch `origin/claude/monetization-status-oqh7s3` only edits docs (phase-numbering clarification; now folded into `docs/DECISIONS.md`).
4. **Report inbox** — user reports land in `corrections`; review via `GET /api/admin/corrections`.

## Risks & known gaps

- No API unit tests; only 4 Playwright specs. Merge to `master` auto-deploys to prod.
- Several hosted-service flags default differently in code vs. docs; production values are only in Azure App Settings (not in repo).
- Anthropic path unproven; app effectively runs on OpenAI.
- **Undocumented Cloudflare Workers Builds integration:** GitHub PR checks show a `Workers Builds: urdumeaning` check (Cloudflare account project `urdumeaning`) that fails instantly on PR #2 (docs-only). The repo has no `wrangler` config and docs say Cloudflare is DNS only (prod web is on Azure). Owner should confirm whether this Cloudflare project is intended; if not, disconnect it in the Cloudflare dashboard, otherwise document it in DEPLOYMENT.md. Observed 2026-11-01; cause not confirmed (dashboard not accessible to agents).
- Legacy docs mention Azure DevOps pipelines (`.azure/`); real CI/CD is GitHub Actions.
- Datadog is optional/not confirmed active; App Insights is the monitoring source of truth.
- Secrets were pasted in chats historically — rotation guidance is in `docs/OPERATIONS.md` (Gmail app password). Happened again 2026-11-01 during this verification session (`az webapp config appsettings list` output included full plaintext secrets); see production snapshot note above.

## Suggested next steps (propose to owner, don't assume)

1. ~~Verify production health~~ — done 2026-11-01, see production snapshot above. `WordGeneration__Enabled` resolved as intentional policy.
2. Decide: keep SEO cap at 1000 or raise, based on monitoring — now has real data (see `/api/word/*` traffic above) to decide from.
3. Decide whether to start monetization (build Phase 6) or more content-quality work.
4. Add a minimal API test project and a CI build/test gate on PRs.
5. Resolve the Cloudflare Workers Builds question (needs owner to paste dashboard info — not accessible to agents).

## Open questions for owner

See `PROJECT_PLAN.md` -> "Questions for Owner" (some are probably answered already — ask and clean up).
