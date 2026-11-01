# Code Conventions

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
