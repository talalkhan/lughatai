# UrduMeaning — Agent Instructions

> **You are the primary developer and owner of this app.** This file is the single entry point for every agent (Claude Code, Codex, Antigravity, anything else). `CLAUDE.md` just imports it.
> The owner (ThetaFoundry LLC) should be able to ask you "what's the status?" or any question about the app and get a correct, current answer. That is only possible if you follow the session protocol below.

## What the app is

UrduMeaning (urdumeaning.com) is an AI-generated English-to-Urdu dictionary. Cache-first: AI generates a word once, the result is stored forever in PostgreSQL (JSONB), and later lookups never touch AI. Stack: Next.js 14 (`web/`), ASP.NET Core 8 (`api/`), PostgreSQL 16, optional Redis, Azure (App Service, Blob, Speech), Cloudflare DNS. PRD: `docs/UrduMeaning_PRD_v1.2.docx`.

## Session protocol (mandatory)

**1. Start — get current before doing anything**
1. Run `bash scripts/agent_status.sh` (Claude Code runs it automatically). It shows branch, recent commits, unmerged remote branches, and warns if `docs/STATUS.md` is stale.
2. Read `docs/STATUS.md` (what is true now, what is in flight, risks, next steps).
3. Skim the doc map below; open what the task needs. If STATUS.md disagrees with `git log` or the code, **trust the code**, then fix STATUS.md.

**2. Answering "status" or "how does X work" questions**
Answer from `docs/STATUS.md` + `docs/ARCHITECTURE.md`, verified against git/code. Always say what you verified in this session vs. what is carried over from the docs (production state in Azure is NOT visible from the repo — label it with its "as of" date). Never invent production numbers.

**3. During work**
Follow the guardrails below and `docs/CONVENTIONS.md`. Work on the branch you were assigned; open a PR to `master` (merging to `master` auto-deploys the API/web to production).

**4. Before you finish (every session, even small ones)**
- Update `docs/STATUS.md`: bump "Last updated / by", move items between In flight / Next / Done, record new risks or decisions.
- Mark tasks in `PROJECT_PLAN.md` (roadmap).
- Add a dated row at the top of the Work Log in `docs/HISTORY.md` for anything meaningful.
- If you changed behaviour described in `docs/ARCHITECTURE.md`, `COST_CONTROLS.md`, `CONFIG.md` or `OPERATIONS.md`, update that file in the same commit.
- Commit docs together with the code. CI (`docs-freshness.yml`) fails PRs that change `api/`, `web/`, `infrastructure/` or `scripts/` without touching `docs/STATUS.md`.

## Doc map (each fact lives in exactly one place)

| File | Purpose | Changes |
|---|---|---|
| `docs/STATUS.md` | **Current state**: health, in flight, next, risks, open questions | Every session |
| `PROJECT_PLAN.md` | Forward roadmap/backlog (Phase 6 monetization, blockers, owner questions) | When tasks move |
| `docs/ARCHITECTURE.md` | How the system works: request flow, backend/frontend map, tables, CI/deploy, schema, endpoints | When behaviour changes |
| `docs/COST_CONTROLS.md` | **AI spend guardrails and the incidents behind them** — read before any AI-related change | Rarely |
| `docs/OPERATIONS.md` | Local dev, DB backup/restore, word-population pipeline, report-email setup | When procedures change |
| `docs/DEPLOYMENT.md` | Azure beta deployment, secrets, app settings, admin ops | When infra changes |
| `docs/CONFIG.md` | Config/env templates | When config keys change |
| `docs/CONVENTIONS.md` | Backend/frontend code conventions | Rarely |
| `docs/DECISIONS.md` | Locked decisions + phase-numbering key | Only by owner instruction |
| `docs/HISTORY.md` | Append-only work log and detailed past notes (incidents, data-quality work) | Append only |
| `docs/archive/COMPLETED_PHASES.md` | Old task specs for finished phases 0–5 | Never |
| `docs/BETA_INFRA_PLAN.md` | Original beta infra plan | Reference |

## Hard guardrails (summary — full detail in `docs/COST_CONTROLS.md`)

1. **No unintended AI spend.** Production runs with `WordGeneration:Enabled=false`, `WordGeneration:RequireApprovedWord=true`, `BatchProcessor:Enabled=false`, `Enrichment:Enabled=false` (capped 30/hr if on). Never enable or loosen these without explicit owner instruction. Bulk generation uses `scripts/batch_submit_openai.ps1` (Batch API), never the live processor.
2. **Never call AI from controllers**; go through `WordService`. Don't remove the `React.cache()` wrapper in `web/app/word/[slug]/page.tsx`, the slug validation, or `web/middleware.ts` crawler rules.
3. **Never run `docker compose down -v`** or any destructive DB operation without a fresh backup (`data/word_definitions_backup*`). Look at a target before deleting or overwriting.
4. **No secrets in the repo.** Config via env vars / Azure App Settings. `api/appsettings.Development.json` is gitignored.
5. **Don't change locked decisions** (`docs/DECISIONS.md`) or the AI prompt without updating `api/Prompts/*` and telling the owner.
6. **Outward-facing or hard-to-reverse actions need owner confirmation**: production deploys of risky changes, Azure setting changes, sending email, spending money, force-pushing, deleting data.
7. No `TODO` comments, `console.log`, or `Console.WriteLine` in committed code; pending work belongs in `PROJECT_PLAN.md`.

## Quick facts

- Local: `docker compose up -d` (Postgres :5433, Redis :6379) -> `cd api; dotnet ef database update; dotnet run` (:5000) -> `cd web; npm install; npm run dev` (:3000). Full steps in `docs/OPERATIONS.md`.
- Tests: Playwright E2E in `web/e2e/`. There is no API unit-test project.
- Production: Azure UAE North, `lughatai-beta-api` / `lughatai-beta-web`, Postgres `lughatai-beta-db`, App Insights `lughatai-beta-insights`.
- Scripts in `scripts/` are mostly PowerShell and need production credentials most agents lack.
- "Phase" is ambiguous (product vs build) — see `docs/DECISIONS.md`.
