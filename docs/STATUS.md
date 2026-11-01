# UrduMeaning — Current Status

> **The first thing to read after AGENTS.md.** Keep it short and true. Update at the end of every session.
> Items marked *(as of DATE)* come from docs/people, not from a live check — the repo cannot see Azure. Re-verify before quoting them as fact.

```
Last updated : 2026-11-01
Updated by   : Claude (docs restructure session)
Repo head    : master @ 9793df4 (2026-06-03) — no code commits since; the gap to today is ~5 months
Phase        : LIVE (beta) at urdumeaning.com
```

## One-paragraph summary

UrduMeaning is live in beta. English-to-Urdu entries are AI-generated once and served from Postgres. Core product (search, word pages, browse, WOTD, accounts, favorites/history, flashcards, quiz, PWA/offline, push, audio, report-an-error) is built and deployed. All live AI generation is deliberately switched OFF in production to protect spend; the dictionary is served from ~184k pre-generated definitions. The last work was data-quality repair and a controlled reopening of SEO crawling. Monetization (Stripe) has not started.

## Production snapshot *(as of 2026-06-03 unless noted — unverified today)*

| Item | Value |
|---|---|
| Definitions in Azure Postgres | 184,072 (structural audit clean: 0 missing stage, 0 headword mismatches, 0 empty meanings, 0 missing Nastaliq). Older docs say 45,500 — that was 2026-05-24 and is stale |
| Models in DB | mostly `gpt-4o-mini` / `gpt-4o-mini-batch`; ~500 `gpt-5.5` repairs, 100 `gpt-5.4-mini`, 100 `claude-sonnet-4-6`; stage `core` ≈ 69.9k, `enriched` ≈ 115k |
| Live AI generation | OFF (`WordGeneration:Enabled=false`, `RequireApprovedWord=true`) |
| BatchProcessor / Enrichment | OFF |
| Redis | OFF (`Redis:Enabled=false`) |
| AI models configured | `AI:BatchModel` = `AI:LiveModel` = `gpt-4o-mini` (routes straight to OpenAI) |
| Anthropic account | $0 balance as of 2026-05-27; Claude model names never confirmed valid |
| SEO | `/word/` open to Google/Bing/DDG/etc.; sitemap = existing words, capped 1000 (`SITEMAP_WORD_LIMIT`); noisy bots get 429 |
| Hosting | Azure UAE North, B2 plan, Cloudflare DNS; weekly DB backup to Blob (12-week retention) |
| Report emails | Gmail SMTP to admin; enabled via Azure app settings |

## What is done

Build phases 0–5 complete (backend, frontend, deploy, accounts, PWA). Cost-control hardening after three credit-drain incidents (2026-05-27). Trusted-word bulk generation via OpenAI Batch (SCOWL+WordNet list, 0 trusted words missing). Report feedback with definition snapshots. Details: `docs/HISTORY.md`.

## In flight / open

1. **SEO reopening monitoring** — after 2026-06-03 reopening, App Insights Dependencies to `api.openai.com` / `api.anthropic.com` must stay at zero; check `/api/word/*` volume and 404s before raising `SITEMAP_WORD_LIMIT`. *No evidence in the repo this was ever checked.*
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
- Secrets were pasted in chats historically — rotation guidance is in `docs/OPERATIONS.md` (Gmail app password).

## Suggested next steps (propose to owner, don't assume)

1. Verify production health (Azure settings match table above, App Insights AI dependency = 0, word count) and refresh this file.
2. Decide: keep SEO cap at 1000 or raise, based on monitoring.
3. Decide whether to start monetization (build Phase 6) or more content-quality work.
4. Add a minimal API test project and a CI build/test gate on PRs.

## Open questions for owner

See `PROJECT_PLAN.md` -> "Questions for Owner" (some are probably answered already — ask and clean up).
