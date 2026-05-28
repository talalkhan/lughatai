import {
  ApiError,
  AuthResult,
  BrowseParams,
  BrowseResult,
  FavoriteEntry,
  HistoryEntry,
  RomanSearchResult,
  SearchResult,
  WordData,
} from "./types";

const BASE_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:5000";

// SSR (Node.js) waits up to 60 s so AI-generated words can complete.
// Browser keeps 5 s for snappy search / interactive calls.
const API_TIMEOUT_MS = typeof window === "undefined" ? 60_000 : 5_000;

// ── Base fetch helpers ─────────────────────────────────────────────────────

async function apiFetch<T>(path: string, options?: RequestInit): Promise<T> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), API_TIMEOUT_MS);

  let res: Response;
  try {
    res = await fetch(`${BASE_URL}${path}`, {
      next: { revalidate: 60 },
      credentials: "include",
      ...options,
      signal: options?.signal ?? controller.signal,
    });
  } catch (error) {
    if (error instanceof Error && error.name === "AbortError") {
      throw new ApiError(504, "API request timed out");
    }
    throw error;
  } finally {
    clearTimeout(timeout);
  }

  if (!res.ok) {
    const body = await res.json().catch(() => ({ error: res.statusText }));
    throw new ApiError(res.status, body?.error ?? res.statusText);
  }

  return res.json() as Promise<T>;
}

function authHeaders(token: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${token}`,
  };
}

// ── Words (public) ─────────────────────────────────────────────────────────

export async function getWord(word: string): Promise<WordData> {
  return apiFetch<WordData>(`/api/word/${encodeURIComponent(word)}`);
}

export async function searchWords(
  q: string,
  limit = 10
): Promise<SearchResult[]> {
  return apiFetch<SearchResult[]>(
    `/api/search?q=${encodeURIComponent(q)}&limit=${limit}`
  );
}

export async function searchRomanUrdu(q: string): Promise<RomanSearchResult> {
  return apiFetch<RomanSearchResult>(
    `/api/search/roman?q=${encodeURIComponent(q)}`
  );
}

export async function getWordOfTheDay(): Promise<WordData> {
  return apiFetch<WordData>("/api/word-of-the-day");
}

export async function browseWords(params: BrowseParams): Promise<BrowseResult> {
  const qs = new URLSearchParams();
  if (params.context) qs.set("context", params.context);
  if (params.difficulty) qs.set("difficulty", params.difficulty);
  if (params.cefr) qs.set("cefr", params.cefr);
  if (params.page) qs.set("page", String(params.page));
  if (params.limit) qs.set("limit", String(params.limit));
  return apiFetch<BrowseResult>(`/api/browse?${qs.toString()}`);
}

export async function getRandomWord(difficulty?: string): Promise<WordData> {
  const qs = difficulty ? `?difficulty=${encodeURIComponent(difficulty)}` : "";
  return apiFetch<WordData>(`/api/word/random${qs}`);
}

// ── Auth ───────────────────────────────────────────────────────────────────

export async function register(
  username: string,
  email: string,
  password: string
): Promise<AuthResult> {
  return apiFetch<AuthResult>("/api/auth/register", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ username, email, password }),
    cache: "no-store",
  });
}

export async function login(
  email: string,
  password: string
): Promise<AuthResult> {
  return apiFetch<AuthResult>("/api/auth/login", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
    cache: "no-store",
  });
}

export async function refreshToken(): Promise<AuthResult> {
  return apiFetch<AuthResult>("/api/auth/refresh", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
    cache: "no-store",
  });
}

export async function logout(): Promise<void> {
  await apiFetch<void>("/api/auth/logout", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({}),
    cache: "no-store",
  });
}

// ── Favorites ──────────────────────────────────────────────────────────────

export async function getFavorites(accessToken: string): Promise<FavoriteEntry[]> {
  return apiFetch<FavoriteEntry[]>("/api/user/favorites", {
    headers: authHeaders(accessToken),
    cache: "no-store",
  });
}

export async function addFavorite(word: string, accessToken: string): Promise<void> {
  await apiFetch<void>(`/api/user/favorites/${encodeURIComponent(word)}`, {
    method: "POST",
    headers: authHeaders(accessToken),
    cache: "no-store",
  });
}

export async function removeFavorite(word: string, accessToken: string): Promise<void> {
  await apiFetch<void>(`/api/user/favorites/${encodeURIComponent(word)}`, {
    method: "DELETE",
    headers: authHeaders(accessToken),
    cache: "no-store",
  });
}

export async function getFavoriteStatus(
  word: string,
  accessToken: string
): Promise<boolean> {
  const r = await apiFetch<{ favorited: boolean }>(
    `/api/user/favorites/${encodeURIComponent(word)}/status`,
    { headers: authHeaders(accessToken), cache: "no-store" }
  );
  return r.favorited;
}

// ── History ────────────────────────────────────────────────────────────────

export async function getHistory(accessToken: string): Promise<HistoryEntry[]> {
  return apiFetch<HistoryEntry[]>("/api/user/history", {
    headers: authHeaders(accessToken),
    cache: "no-store",
  });
}

export async function clearHistory(accessToken: string): Promise<void> {
  await apiFetch<void>("/api/user/history", {
    method: "DELETE",
    headers: authHeaders(accessToken),
    cache: "no-store",
  });
}

// ── Corrections (flag) ─────────────────────────────────────────────────────

export async function flagWord(
  word: string,
  reason: string,
  notes: string | undefined,
  accessToken?: string
): Promise<void> {
  const headers: HeadersInit = { "Content-Type": "application/json" };
  if (accessToken) headers["Authorization"] = `Bearer ${accessToken}`;
  await apiFetch<void>(`/api/word/${encodeURIComponent(word)}/flag`, {
    method: "POST",
    headers,
    body: JSON.stringify({ reason, notes }),
    cache: "no-store",
  });
}
