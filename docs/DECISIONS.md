# Locked Architecture Decisions

> Final decisions from PRD Section 14. Do not change without explicit owner instruction.

## Phase numbering — two schemes, do not conflate

"Phase" means two things. **Product phase** (PRD Section 14, numbered 1–3) is what ships to users. **Build phase** (PROJECT_PLAN.md, numbered 0–6) is an execution milestone. When you cite a phase, say which kind.

| Product phase | Delivers | Build phases |
|---|---|---|
| Phase 1 | MVP: search, word detail, WOTD, browse, deployed | 0 Bootstrap, 1 MVP Backend, 2 MVP Frontend, 3 Integration & Deploy |
| Phase 2 | Accounts: auth, favorites, history, flashcards, quiz | 4 User Accounts |
| Phase 3 | PWA/offline, Devanagari, monetization | 5 PWA, 6 Monetization |

So "Monetization — product Phase 3" and "build Phase 6 — Monetization" are the same work.
(Adopted from the unmerged branch `claude/monetization-status-oqh7s3`.)

## Decisions

| # | Decision | Detail |
|---|----------|--------|
| 1 | App name | UrduMeaning |
| 2 | Roman Urdu search | String match against stored `roman_urdu` only (product Phase 1). AI-assisted fallback exists but is gated by `RomanSearchAI:Enabled` (off). |
| 3 | Audio generation | Lazy — generate on first play, cache forever in Azure Blob |
| 4 | Devanagari | Skipped in product Phases 1–2. JSON field reserved. Populate in product Phase 3. |
| 5 | Islamic references | Only include when AI finds a genuine verifiable reference. Null otherwise. |
| 6 | Poetry attribution | AI-generated with disclaimer; verification via admin endpoints. |
| 7 | Offline storage | PWA service worker + IndexedDB (built, build Phase 5). |
| 8 | User corrections | Flag button only. Logs to `corrections` table. No free-text. |
| 9 | Platform | Responsive web (Next.js) + PWA. No native app. |
| 10 | Monetization | Stripe Checkout (web-native). Product Phase 3 = build Phase 6 — not started. |
