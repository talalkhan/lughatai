# UrduMeaning — Roadmap & Backlog

> This file is the **forward-looking plan only**. Where things stand now: `docs/STATUS.md`.
> What already happened: `docs/HISTORY.md`. Archived specs for Phases 0–5: `docs/archive/COMPLETED_PHASES.md`.
> Update this file when you start, finish or add a task; mirror the change in `docs/STATUS.md`.

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 0 | Bootstrap | [x] Complete |
| 1 | MVP Backend | [x] Complete |
| 2 | MVP Frontend | [x] Complete |
| 3 | Integration & Deploy | [x] Complete (live at urdumeaning.com) |
| 4 | User accounts & Phase 2 features | [x] Complete |
| 5 | PWA | [x] Complete |
| 6 | Monetization | [ ] Not started (0 / 8) |

Also in flight outside the numbered phases: data-quality work (semantic repair of Urdu translations) and SEO/crawler reopening — see STATUS.md.

## Status Key

```
[ ]  Not started
[~]  In progress (add agent name + date: [~ Codex 2026-04-29])
[x]  Complete (add date)
[!]  Blocked (describe blocker in Notes)
[-]  Skipped / deferred (with reason)
```

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
