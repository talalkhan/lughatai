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

  function updateFilter(key: string, value: string | undefined) {
    const p = new URLSearchParams(searchParams.toString());
    if (value) p.set(key, value);
    else p.delete(key);
    router.push(`/browse?${p.toString()}`);
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
      {/* Filters */}
      <div className="space-y-4">
        <div>
          <p className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">Difficulty</p>
          <div className="flex flex-wrap gap-2">
            <FilterChip label="All" active={!difficulty} onClick={() => updateFilter("difficulty", undefined)} />
            {DIFFICULTIES.map((d) => (
              <FilterChip key={d} label={d} active={difficulty === d} onClick={() => updateFilter("difficulty", d)} />
            ))}
          </div>
        </div>
        <div>
          <p className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">CEFR Level</p>
          <div className="flex flex-wrap gap-2">
            <FilterChip label="All" active={!cefr} onClick={() => updateFilter("cefr", undefined)} />
            {CEFR_LEVELS.map((l) => (
              <FilterChip key={l} label={l} active={cefr === l} onClick={() => updateFilter("cefr", l)} />
            ))}
          </div>
        </div>
        <div>
          <p className="text-xs font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">Category</p>
          <div className="flex flex-wrap gap-2">
            <FilterChip label="All" active={!context} onClick={() => updateFilter("context", undefined)} />
            {CONTEXTS.map((c) => (
              <FilterChip key={c} label={c} active={context === c} onClick={() => updateFilter("context", c)} />
            ))}
          </div>
        </div>
      </div>

      {!loading && (
        <p className="text-sm text-gray-500 dark:text-gray-400">
          {total === 0 ? "No words found" : `${total.toLocaleString()} words`}
        </p>
      )}

      {loading ? (
        <div className="grid sm:grid-cols-2 gap-4">
          {Array.from({ length: 6 }).map((_, i) => <WordCardSkeleton key={i} />)}
        </div>
      ) : (
        <>
          <div className="grid sm:grid-cols-2 gap-4">
            {words.map((w) => <WordCard key={w.word} variant="compact" data={w} />)}
          </div>
          {words.length < total && (
            <div className="text-center mt-8">
              <button
                onClick={() => fetchWords(page + 1, false)}
                disabled={loadingMore}
                className="px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-medium transition-colors min-h-[44px] disabled:opacity-50"
              >
                {loadingMore ? "Loading…" : "Load more"}
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
