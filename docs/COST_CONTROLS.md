# AI Cost Controls

> **Read before touching anything AI-related.** Moved verbatim from the old CLAUDE.md.
> Some dated facts below (e.g. Anthropic balance) are snapshots — verify before relying on them.

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

### WordGeneration — ON in production by design; `RequireApprovedWord` is the real gate

| Config key | Default (appsettings.json) | Production (Azure, verified 2026-11-01) | What it controls |
|---|---|---|---|
| `WordGeneration:Enabled` | `false` | **`true`** | Live AI generation in `WordService` for single words not in DB |
| `WordGeneration:RequireApprovedWord` | `true` | `true` | Blocks live AI generation unless the missing word already exists in `approved_words` |
| `Enrichment:Enabled` | `false` | `false` | Background enrichment in `WordEnrichmentProcessor` |

**Policy (confirmed by owner 2026-11-01): generate a word on cache miss regardless of
who or what triggers the lookup** — a real user, Googlebot, or any other crawler. The
source of the request doesn't matter; what matters is whether the word is in
`approved_words`. That whitelist check (`RequireApprovedWord=true`) is the actual safety
control, not the `Enabled` switch — **do not loosen `RequireApprovedWord`**, since that's
what stops crawler-shaped garbage strings (e.g. `producedunderfactorysupervision`) from
reaching AI and getting hallucinated into the DB permanently. The code also blocks
crawler-shaped slugs before generation even reaches the whitelist check: whitespace,
encoded `%...` URLs, `+`, hyphenated/non-alpha slugs, and anything that isn't a clean
single English token.

`approved_words` is the durable validity table; `word_queue` is only batch processing
state and may be empty in production. Use `scripts/populate_approved_words_from_bulk.ps1`
to load the generated 340k-word list into `approved_words`, and use
`scripts/audit_unqueued_definitions.sql` plus `scripts/cleanup_unapproved_definitions.sql`
to inspect/quarantine existing bad generated rows before cleanup.

**History:** `WordGeneration:Enabled=false` was previously documented here as a hard
"must stay off" kill switch, adopted after the BatchProcessor incident below. A live
Azure check on 2026-11-01 found it had actually been `true` since at least 2026-08-04
(774 `api.openai.com` calls recorded in App Insights, rising alongside a crawl-traffic
spike that started 2026-08-31). The owner reviewed this and confirmed it as the intended
policy, not accidental drift — see the policy line above. If a future cost spike requires
freezing generation entirely, set `WordGeneration:Enabled=false` in Azure App Service
config (no deployment needed); under current policy that's an emergency-only action, not
the default state.

SEO crawl control: valid single-word `/word/...` pages can be crawled at high volume and
force SSR to call `/api/word/{word}`, and under current policy that can legitimately
trigger generation for any approved word a crawler happens to hit first — this is
expected, not a leak. `robots.txt` allows `/word/` for general crawlers, `sitemap.xml`
lists only existing words returned by `/api/browse` and is capped by `SITEMAP_WORD_LIMIT`
(default 1000), and `web/middleware.ts` still blocks high-noise crawlers such as
Ahrefs/Semrush/GPTBot while allowing Googlebot/Bingbot/DuckDuckBot — `RequireApprovedWord`
remains the backstop against those blocked bots' crawl patterns if any slip through.

Monitor Application Insights Dependencies for `api.openai.com` periodically to sanity-check
volume/cost stays proportionate to real dictionary growth; `api.anthropic.com` should stay
at zero until the Anthropic account/model path is deliberately revisited. Also keep an eye
on `/api/word/*` request volume and 404s before raising `SITEMAP_WORD_LIMIT` further.

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
