"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { WordData } from "@/lib/types";

interface CachedWord extends WordData {
  saved_at: number;
}

export default function OfflinePage() {
  const [recentWords, setRecentWords] = useState<WordData[]>([]);

  useEffect(() => {
    // Show the last few words cached in IndexedDB
    if (typeof indexedDB === "undefined") return;

    const DB_NAME = "urdumeaning";
    const req = indexedDB.open(DB_NAME, 1);
    req.onsuccess = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("words")) return;
      const all = db.transaction("words", "readonly").objectStore("words").getAll();
      all.onsuccess = () => {
        const sorted = (all.result as CachedWord[])
          .sort((a, b) => b.saved_at - a.saved_at)
          .slice(0, 8);
        setRecentWords(sorted);
      };
    };
  }, []);

  return (
    <main className="max-w-lg mx-auto px-4 py-16 text-center">
      <p className="text-5xl mb-4">📡</p>
      <h1 className="text-2xl font-bold mb-2">You&apos;re offline</h1>
      <p className="text-gray-600 dark:text-gray-400 mb-8">
        No internet connection. Browse words you&apos;ve already looked up.
      </p>

      {recentWords.length > 0 && (
        <>
          <h2 className="text-left text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
            Cached words
          </h2>
          <ul className="text-left divide-y divide-gray-100 dark:divide-gray-800 rounded-xl border border-gray-200 dark:border-gray-700 overflow-hidden mb-8">
            {recentWords.map(w => (
              <li key={w.word}>
                <Link
                  href={`/word/${w.word}`}
                  className="flex items-center justify-between gap-4 px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-800 transition-colors"
                >
                  <div>
                    <p className="font-medium capitalize">{w.word}</p>
                    {w.script_variants?.nastaliq && (
                      <span dir="rtl" lang="ur" className="font-nastaliq text-sm text-gray-600 dark:text-gray-400">
                        {w.script_variants.nastaliq}
                      </span>
                    )}
                  </div>
                  {w.learning?.emoji && <span>{w.learning.emoji}</span>}
                </Link>
              </li>
            ))}
          </ul>
        </>
      )}

      <Link
        href="/"
        className="inline-block px-6 py-3 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg min-h-[44px]"
      >
        Try again
      </Link>
    </main>
  );
}
