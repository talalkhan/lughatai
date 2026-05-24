"use client";

import { useCallback, useEffect, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import WordCard from "@/components/WordCard";
import WordCardSkeleton from "@/components/skeletons/WordCardSkeleton";
import { browseWords } from "@/lib/api";
import { WordSummary } from "@/lib/types";

const DIFFICULTIES = ["beginner", "intermediate", "advanced", "expert"];
const CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];
const CONTEXTS = ["religion", "literature", "poetry", "business", "science", "philosophy", "medicine", "daily"];

function FilterChip({ label, active, onClick }: { label: string; active: boolean; onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      className={`px-4 py-2 rounded-full text-sm font-medium transition-colors min-h-[44px]
        ${active
          ? "bg-indigo-600 text-white"
          : "bg-gray-100 dark:bg-gray-800 text-gray-700 dark:text-gray-300 hover:bg-gray-200 dark:hover:bg-gray-700"
        }`}
    >
      {label}
    </button>
  );
}

export default function BrowseClient() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [words, setWords] = useState<WordSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [loading, setLoading] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  const context = searchParams.get("context") ?? undefined;
  const difficulty = searchParams.get("difficulty") ?? undefined;
  const cefr = searchParams.get("cefr") ?? undefined;
  const activeFilters = [
    difficulty ? `Difficulty: ${difficulty}` : null,
    cefr ? `CEFR: ${cefr}` : null,
    context ? `Category: ${context}` : null,
  ].filter((value): value is string => !!value);
  const hasFilters = activeFilters.length > 0;

  function updateFilter(key: string, value: string | undefined) {
    const p = new URLSearchParams(searchParams.toString());
    if (value) p.set(key, value);
    else p.delete(key);
    const query = p.toString();
    router.push(query ? `/browse?${query}` : "/browse");
  }

  const fetchWords = useCallback(async (p: number, replace: boolean) => {
    if (replace) setLoading(true);
    else setLoadingMore(true);
    try {
      const result = await browseWords({ context, difficulty, cefr, page: p, limit: 20 });
      setWords((prev) => (replace ? result.words : [...prev, ...result.words]));
      setTotal(result.total);
      setPage(p);
    } finally {
      setLoading(false);
      setLoadingMore(false);
    }
  }, [context, difficulty, cefr]);

  useEffect(() => {
    setPage(1);
    fetchWords(1, true);
  }, [fetchWords]);

  return (
    <div className="space-y-6">
      <div className="max-w-3xl">
        <p className="text-xs font-semibold uppercase tracking-[0.25em] text-gray-500 dark:text-gray-400">
          Explore the dictionary
        </p>
        <h1 className="mt-2 text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100">
          Browse Words
        </h1>
        <p className="mt-2 text-sm text-gray-600 dark:text-gray-400">
          Filter by difficulty, CEFR level, or context and move through the dictionary intentionally.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)] lg:gap-8">
        <aside className="lg:sticky lg:top-28 lg:self-start">
          <div className="rounded-3xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-900">
            <div className="mb-5 flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">Filters</p>
                <p className="text-xs text-gray-500 dark:text-gray-400">Dial the word list down quickly.</p>
              </div>
              {hasFilters && (
                <button
                  onClick={() => router.push("/browse")}
                  className="text-sm font-medium text-indigo-600 hover:text-indigo-700 dark:text-indigo-300 dark:hover:text-indigo-200"
                >
                  Clear all
                </button>
              )}
            </div>

            <div className="space-y-5">
              <div>
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Difficulty</p>
                <div className="flex flex-wrap gap-2">
                  <FilterChip label="All" active={!difficulty} onClick={() => updateFilter("difficulty", undefined)} />
                  {DIFFICULTIES.map((d) => (
                    <FilterChip key={d} label={d} active={difficulty === d} onClick={() => updateFilter("difficulty", d)} />
                  ))}
                </div>
              </div>
              <div>
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">CEFR Level</p>
                <div className="flex flex-wrap gap-2">
                  <FilterChip label="All" active={!cefr} onClick={() => updateFilter("cefr", undefined)} />
                  {CEFR_LEVELS.map((l) => (
                    <FilterChip key={l} label={l} active={cefr === l} onClick={() => updateFilter("cefr", l)} />
                  ))}
                </div>
              </div>
              <div>
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-500 dark:text-gray-400">Category</p>
                <div className="flex flex-wrap gap-2">
                  <FilterChip label="All" active={!context} onClick={() => updateFilter("context", undefined)} />
                  {CONTEXTS.map((c) => (
                    <FilterChip key={c} label={c} active={context === c} onClick={() => updateFilter("context", c)} />
                  ))}
                </div>
              </div>
            </div>
          </div>
        </aside>

        <section className="space-y-5">
          <div className="rounded-3xl border border-gray-200 bg-white p-5 shadow-sm dark:border-gray-700 dark:bg-gray-900">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
              <div>
                <p className="text-sm font-semibold text-gray-900 dark:text-gray-100">
                  {loading ? "Loading words…" : total === 0 ? "No words found" : `${total.toLocaleString()} words`}
                </p>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  {hasFilters ? "Filtered results tailored to your current selection." : "A broad cross-section of the dictionary."}
                </p>
              </div>
              {hasFilters && (
                <div className="flex flex-wrap gap-2">
                  {activeFilters.map((filter) => (
                    <span
                      key={filter}
                      className="rounded-full bg-indigo-50 px-3 py-1 text-xs font-medium text-indigo-700 dark:bg-indigo-950 dark:text-indigo-300"
                    >
                      {filter}
                    </span>
                  ))}
                </div>
              )}
            </div>
          </div>

          {loading ? (
            <div className="grid gap-4 md:grid-cols-2">
              {Array.from({ length: 6 }).map((_, i) => <WordCardSkeleton key={i} />)}
            </div>
          ) : (
            <>
              <div className="grid gap-4 md:grid-cols-2">
                {words.map((w) => <WordCard key={w.word} variant="compact" data={w} />)}
              </div>
              {words.length < total && (
                <div className="text-center pt-2">
                  <button
                    onClick={() => fetchWords(page + 1, false)}
                    disabled={loadingMore}
                    className="min-h-[48px] rounded-xl bg-indigo-600 px-6 py-3 font-medium text-white transition-colors hover:bg-indigo-700 disabled:opacity-50"
                  >
                    {loadingMore ? "Loading…" : "Load more"}
                  </button>
                </div>
              )}
            </>
          )}
        </section>
      </div>
    </div>
  );
}
