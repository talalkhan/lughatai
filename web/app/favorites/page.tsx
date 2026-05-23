"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/lib/auth";
import { getFavorites, removeFavorite } from "@/lib/api";
import { FavoriteEntry } from "@/lib/types";

export default function FavoritesPage() {
  const { user, accessToken, isLoading: authLoading } = useAuth();
  const [favorites, setFavorites] = useState<FavoriteEntry[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!accessToken) { setLoading(false); return; }

    getFavorites(accessToken)
      .then(setFavorites)
      .catch(() => setError("Could not load favorites."))
      .finally(() => setLoading(false));
  }, [accessToken, authLoading]);

  async function handleRemove(word: string) {
    if (!accessToken) return;
    setFavorites(prev => prev.filter(f => f.word !== word));
    await removeFavorite(word, accessToken).catch(() => {});
  }

  if (authLoading || loading) {
    return (
      <main className="max-w-2xl mx-auto px-4 py-12">
        <div className="animate-pulse space-y-4">
          {[...Array(5)].map((_, i) => (
            <div key={i} className="h-20 bg-gray-200 dark:bg-gray-800 rounded-lg" />
          ))}
        </div>
      </main>
    );
  }

  if (!user) {
    return (
      <main className="max-w-2xl mx-auto px-4 py-12 text-center">
        <h1 className="text-2xl font-bold mb-4">Your Favorites</h1>
        <p className="text-gray-600 dark:text-gray-400 mb-6">
          Sign in to save and view your favorite words.
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
        <h1 className="text-2xl font-bold">Your Favorites</h1>
        <Link href="/" className="text-sm text-emerald-600 dark:text-emerald-400 hover:underline">
          ← Home
        </Link>
      </div>

      {error && (
        <p className="text-red-600 dark:text-red-400 mb-4">{error}</p>
      )}

      {favorites.length === 0 ? (
        <div className="text-center py-16">
          <p className="text-4xl mb-4">📚</p>
          <p className="text-gray-600 dark:text-gray-400">
            No favorites yet. Look up a word and save it with the ♥ button.
          </p>
        </div>
      ) : (
        <ul className="space-y-3">
          {favorites.map(entry => (
            <li
              key={entry.word}
              className="flex items-center justify-between gap-4 p-4 rounded-xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 hover:border-emerald-400 transition-colors"
            >
              <Link href={`/word/${entry.word}`} className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  {entry.emoji && <span className="text-xl">{entry.emoji}</span>}
                  <div>
                    <p className="font-semibold text-gray-900 dark:text-gray-100 capitalize">
                      {entry.word}
                    </p>
                    {entry.urdu && (
                      <span
                        dir="rtl"
                        lang="ur"
                        className="font-nastaliq text-lg text-gray-700 dark:text-gray-300"
                      >
                        {entry.urdu}
                      </span>
                    )}
                    {entry.definition_en && (
                      <p className="text-sm text-gray-500 dark:text-gray-400 truncate">
                        {entry.definition_en}
                      </p>
                    )}
                  </div>
                </div>
              </Link>
              <button
                onClick={() => handleRemove(entry.word)}
                aria-label={`Remove ${entry.word} from favorites`}
                className="p-2 text-red-400 hover:text-red-600 transition-colors min-h-[44px] min-w-[44px] flex items-center justify-center"
              >
                ✕
              </button>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
