"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/lib/auth";
import { clearHistory, getHistory } from "@/lib/api";
import { HistoryEntry } from "@/lib/types";

export default function HistoryPage() {
  const { user, accessToken, isLoading: authLoading } = useAuth();
  const [history, setHistory] = useState<HistoryEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [clearing, setClearing] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!accessToken) { setLoading(false); return; }

    getHistory(accessToken)
      .then(setHistory)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, [accessToken, authLoading]);

  async function handleClear() {
    if (!accessToken) return;
    setClearing(true);
    await clearHistory(accessToken).catch(() => {});
    setHistory([]);
    setClearing(false);
  }

  if (authLoading || loading) {
    return (
      <main className="max-w-2xl mx-auto px-4 py-12">
        <div className="animate-pulse space-y-4">
          {[...Array(8)].map((_, i) => (
            <div key={i} className="h-14 bg-gray-200 dark:bg-gray-800 rounded-lg" />
          ))}
        </div>
      </main>
    );
  }

  if (!user) {
    return (
      <main className="max-w-2xl mx-auto px-4 py-12 text-center">
        <h1 className="text-2xl font-bold mb-4">Your History</h1>
        <p className="text-gray-600 dark:text-gray-400 mb-6">
          Sign in to see your word lookup history.
        </p>
        <Link
          href="/auth"
          className="inline-block px-6 py-3 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg"
        >
          Sign in
        </Link>
      </main>
    );
  }

  return (
    <main className="max-w-2xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold">Your History</h1>
        <div className="flex items-center gap-4">
          {history.length > 0 && (
            <button
              onClick={handleClear}
              disabled={clearing}
              className="text-sm text-red-500 hover:text-red-700 disabled:opacity-50 min-h-[44px] px-2"
            >
              {clearing ? "Clearing…" : "Clear all"}
            </button>
          )}
          <Link href="/" className="text-sm text-emerald-600 dark:text-emerald-400 hover:underline">
            ← Home
          </Link>
        </div>
      </div>

      {history.length === 0 ? (
        <div className="text-center py-16">
          <p className="text-4xl mb-4">🔍</p>
          <p className="text-gray-600 dark:text-gray-400">
            No history yet. Words you look up will appear here.
          </p>
        </div>
      ) : (
        <ul className="divide-y divide-gray-100 dark:divide-gray-800">
          {history.map((entry, i) => (
            <li key={`${entry.word}-${i}`}>
              <Link
                href={`/word/${entry.word}`}
                className="flex items-center justify-between gap-4 py-3 hover:text-emerald-600 dark:hover:text-emerald-400 transition-colors"
              >
                <div className="flex items-center gap-3">
                  {entry.emoji && <span>{entry.emoji}</span>}
                  <div>
                    <p className="font-medium capitalize">{entry.word}</p>
                    {entry.urdu && (
                      <span dir="rtl" lang="ur" className="font-nastaliq text-sm text-gray-600 dark:text-gray-400">
                        {entry.urdu}
                      </span>
                    )}
                  </div>
                </div>
                <time className="text-xs text-gray-400 whitespace-nowrap">
                  {new Date(entry.looked_up_at).toLocaleDateString()}
                </time>
              </Link>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
