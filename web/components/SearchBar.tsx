"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { searchWords } from "@/lib/api";
import { SearchResult } from "@/lib/types";

function DifficultyBadge({ difficulty }: { difficulty?: string }) {
  const colors: Record<string, string> = {
    beginner: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
    intermediate: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
    advanced: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
    expert: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  };
  if (!difficulty) return null;
  return (
    <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${colors[difficulty] ?? "bg-gray-100 text-gray-700"}`}>
      {difficulty}
    </span>
  );
}

export default function SearchBar({
  autoFocus = false,
  variant = "hero",
}: {
  autoFocus?: boolean;
  variant?: "hero" | "compact";
}) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<SearchResult[]>([]);
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [highlighted, setHighlighted] = useState(-1);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (autoFocus) inputRef.current?.focus();
  }, [autoFocus]);

  useEffect(() => {
    if (debounceRef.current) clearTimeout(debounceRef.current);

    if (query.length < 2) {
      setResults([]);
      setOpen(false);
      setLoading(false);
      return;
    }

    // Open immediately with a loading row so user gets instant feedback
    setOpen(true);
    setLoading(true);

    debounceRef.current = setTimeout(async () => {
      try {
        const data = await searchWords(query);
        setResults(data);
        setHighlighted(-1);
      } catch {
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 300);

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current);
    };
  }, [query]);

  function navigate(word: string) {
    setOpen(false);
    setQuery("");
    router.push(`/word/${encodeURIComponent(word.toLowerCase().trim())}`);
  }

  // Total selectable items: cached results + always one "look up with AI" row
  const lookupIndex = results.length;
  const totalItems = loading ? 0 : results.length + 1;

  function handleKeyDown(e: React.KeyboardEvent) {
    if (!open) return;
    if (e.key === "ArrowDown") {
      e.preventDefault();
      if (totalItems > 0) setHighlighted((h) => Math.min(h + 1, totalItems - 1));
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      setHighlighted((h) => Math.max(h - 1, -1));
    } else if (e.key === "Enter") {
      e.preventDefault();
      if (!loading && highlighted >= 0 && highlighted < results.length) {
        navigate(results[highlighted].word);
      } else if (query.trim().length >= 2) {
        navigate(query.trim());
      }
    } else if (e.key === "Escape") {
      setOpen(false);
    }
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (query.trim().length >= 2) navigate(query.trim());
  }

  const compact = variant === "compact";
  const wrapperClass = compact
    ? "relative w-full"
    : "relative w-full max-w-2xl mx-auto";
  const inputClass = compact
    ? "w-full px-4 py-3 text-sm rounded-xl border border-gray-200 dark:border-gray-700 bg-white/90 dark:bg-gray-900/90 focus:outline-none focus:border-indigo-500 dark:focus:border-indigo-400 pr-20 shadow-sm"
    : "w-full px-5 py-4 text-base rounded-2xl border-2 border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 focus:outline-none focus:border-indigo-500 dark:focus:border-indigo-400 pr-24";
  const clearButtonClass = compact
    ? "absolute right-12 p-2 text-gray-400 hover:text-gray-600 min-w-[40px] min-h-[40px] flex items-center justify-center"
    : "absolute right-16 p-2 text-gray-400 hover:text-gray-600 min-w-[44px] min-h-[44px] flex items-center justify-center";
  const searchButtonClass = compact
    ? "absolute right-2 px-3 py-2 min-h-[40px] min-w-[40px] bg-indigo-600 hover:bg-indigo-700 text-white rounded-lg text-sm font-medium transition-colors"
    : "absolute right-2 px-4 py-2 min-h-[44px] min-w-[44px] bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl text-sm font-medium transition-colors";
  const listClass = compact
    ? "absolute z-50 w-full mt-2 bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl shadow-2xl overflow-hidden"
    : "absolute z-50 w-full mt-2 bg-white dark:bg-gray-900 border border-gray-200 dark:border-gray-700 rounded-2xl shadow-xl overflow-hidden";

  return (
    <div className={wrapperClass}>
      <form onSubmit={handleSubmit} role="search">
        <div className="relative flex items-center">
          <input
            ref={inputRef}
            type="search"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKeyDown}
            onFocus={() => query.length >= 2 && setOpen(true)}
            onBlur={() => setTimeout(() => setOpen(false), 150)}
            placeholder="Search any English word…"
            aria-label="Search for a word"
            aria-autocomplete="list"
            className={inputClass}
            style={{ fontSize: "16px" }}
          />
          {query && (
            <button
              type="button"
              onClick={() => { setQuery(""); setResults([]); setOpen(false); inputRef.current?.focus(); }}
              className={clearButtonClass}
              aria-label="Clear search"
            >
              ✕
            </button>
          )}
          <button
            type="submit"
            className={searchButtonClass}
            aria-label="Search"
          >
            →
          </button>
        </div>
      </form>

      {open && (
        <ul
          role="listbox"
          className={listClass}
        >
          {loading ? (
            /* Searching skeleton */
            <li className="flex items-center gap-3 px-5 py-4 text-gray-500 dark:text-gray-400">
              <span className="inline-block w-4 h-4 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin flex-shrink-0" />
              <span className="text-sm">Searching…</span>
            </li>
          ) : (
            <>
              {/* Cached results */}
              {results.map((r, i) => (
                <li
                  key={r.word}
                  role="option"
                  aria-selected={highlighted === i}
                  onMouseEnter={() => setHighlighted(i)}
                  onMouseDown={() => navigate(r.word)}
                  className={`flex items-center justify-between px-5 py-3 cursor-pointer transition-colors
                    ${highlighted === i ? "bg-indigo-50 dark:bg-indigo-950" : "hover:bg-gray-50 dark:hover:bg-gray-800"}`}
                >
                  <div className="flex items-center gap-3">
                    <span className="font-medium text-gray-900 dark:text-gray-100">{r.word}</span>
                    {r.urdu && (
                      <span dir="rtl" lang="ur" className="font-nastaliq text-lg text-gray-600 dark:text-gray-400">
                        {r.urdu}
                      </span>
                    )}
                  </div>
                  <DifficultyBadge difficulty={r.difficulty} />
                </li>
              ))}

              {/* Always-present "Look up with AI" row */}
              <li
                role="option"
                aria-selected={highlighted === lookupIndex}
                onMouseEnter={() => setHighlighted(lookupIndex)}
                onMouseDown={() => navigate(query.trim())}
                className={`flex items-center gap-3 px-5 py-3 cursor-pointer transition-colors
                  ${results.length > 0 ? "border-t border-gray-100 dark:border-gray-800" : ""}
                  ${highlighted === lookupIndex
                    ? "bg-indigo-50 dark:bg-indigo-950"
                    : "hover:bg-gray-50 dark:hover:bg-gray-800"
                  }`}
              >
                <span className="text-lg">✨</span>
                <span className="text-sm text-gray-600 dark:text-gray-400">
                  {results.length === 0 ? (
                    <>
                      No cached results — look up{" "}
                      <span className="font-semibold text-gray-900 dark:text-gray-100">
                        &ldquo;{query}&rdquo;
                      </span>{" "}
                      with AI
                    </>
                  ) : (
                    <>
                      Look up{" "}
                      <span className="font-semibold text-gray-900 dark:text-gray-100">
                        &ldquo;{query}&rdquo;
                      </span>{" "}
                      with AI
                    </>
                  )}
                </span>
                <span className="ml-auto text-indigo-500 dark:text-indigo-400 text-sm font-medium">→</span>
              </li>
            </>
          )}
        </ul>
      )}
    </div>
  );
}
