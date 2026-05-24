"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/lib/auth";
import { getFavorites, getRandomWord } from "@/lib/api";
import { FlashcardState, WordData } from "@/lib/types";

// ── SM-2 Algorithm ──────────────────────────────────────────────────────────
// quality: 0=blackout, 1=wrong, 2=wrong+hint, 3=correct+hard, 4=correct, 5=perfect
function sm2(card: FlashcardState, quality: number): FlashcardState {
  let { easeFactor, interval, repetitions } = card;

  if (quality < 3) {
    repetitions = 0;
    interval = 1;
  } else {
    if (repetitions === 0) interval = 1;
    else if (repetitions === 1) interval = 6;
    else interval = Math.round(interval * easeFactor);
    repetitions += 1;
  }

  easeFactor = Math.max(
    1.3,
    easeFactor + 0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02)
  );

  const nextReview = new Date();
  nextReview.setDate(nextReview.getDate() + interval);

  return {
    ...card,
    easeFactor,
    interval,
    repetitions,
    nextReview: nextReview.toISOString(),
    lastQuality: quality,
  };
}

const STORAGE_KEY = "urdumeaning_flashcards";

function loadStates(): Record<string, FlashcardState> {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}");
  } catch {
    return {};
  }
}

function saveState(state: FlashcardState) {
  const all = loadStates();
  all[state.word] = state;
  localStorage.setItem(STORAGE_KEY, JSON.stringify(all));
}

function getDueCards(states: Record<string, FlashcardState>): FlashcardState[] {
  const now = new Date();
  return Object.values(states).filter(s => new Date(s.nextReview) <= now);
}

function initCard(word: string): FlashcardState {
  return {
    word,
    easeFactor: 2.5,
    interval: 0,
    repetitions: 0,
    nextReview: new Date().toISOString(),
    lastQuality: -1,
  };
}

// ── Component ───────────────────────────────────────────────────────────────

type Stage = "front" | "back" | "done";

export default function FlashcardsPage() {
  const { user, accessToken, isLoading: authLoading } = useAuth();
  const [deck, setDeck] = useState<WordData[]>([]);
  const [currentIndex, setCurrentIndex] = useState(0);
  const [stage, setStage] = useState<Stage>("front");
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState({ reviewed: 0, due: 0 });

  const loadDeck = useCallback(async () => {
    setLoading(true);
    const states = loadStates();

    let words: string[] = [];

    if (accessToken) {
      // Use favorites as the deck if logged in
      const favs = await getFavorites(accessToken).catch(() => []);
      words = favs.map(f => f.word);
    }

    if (words.length === 0) {
      // Fallback: random words
      const rands = await Promise.allSettled(
        Array.from({ length: 10 }, () => getRandomWord())
      );
      words = rands
        .filter((r): r is PromiseFulfilledResult<WordData> => r.status === "fulfilled")
        .map(r => r.value.word);
    }

    // Ensure all words have a flashcard state
    words.forEach(w => {
      if (!states[w]) saveState(initCard(w));
    });

    const due = getDueCards(loadStates()).filter(s => words.includes(s.word));
    setStats({ reviewed: 0, due: due.length });

    if (due.length === 0) {
      setDeck([]);
      setLoading(false);
      return;
    }

    // Fetch full word data for due cards
    const fetched = await Promise.allSettled(
      due.slice(0, 20).map(s =>
        fetch(
          `${process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:5000"}/api/word/${s.word}`
        ).then(r => r.json() as Promise<WordData>)
      )
    );
    const cards = fetched
      .filter((r): r is PromiseFulfilledResult<WordData> => r.status === "fulfilled")
      .map(r => r.value);

    setDeck(cards);
    setCurrentIndex(0);
    setStage("front");
    setLoading(false);
  }, [accessToken]);

  useEffect(() => {
    if (!authLoading) loadDeck();
  }, [authLoading, loadDeck]);

  function handleQuality(quality: number) {
    const card = deck[currentIndex];
    const states = loadStates();
    const current = states[card.word] ?? initCard(card.word);
    saveState(sm2(current, quality));

    setStats(s => ({ ...s, reviewed: s.reviewed + 1 }));

    if (currentIndex + 1 >= deck.length) {
      setStage("done");
    } else {
      setCurrentIndex(i => i + 1);
      setStage("front");
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────

  if (authLoading || loading) {
    return (
      <main className="max-w-lg mx-auto px-4 py-12 text-center">
        <div className="animate-pulse">
          <div className="h-64 bg-gray-200 dark:bg-gray-800 rounded-2xl mb-4" />
          <div className="h-10 bg-gray-200 dark:bg-gray-800 rounded-lg" />
        </div>
      </main>
    );
  }

  if (deck.length === 0 || stage === "done") {
    return (
      <main className="max-w-lg mx-auto px-4 py-16 text-center">
        <p className="text-5xl mb-4">🎉</p>
        <h1 className="text-2xl font-bold mb-2">
          {stats.reviewed > 0 ? "Session complete!" : "All caught up!"}
        </h1>
        <p className="text-gray-600 dark:text-gray-400 mb-2">
          {stats.reviewed > 0
            ? `You reviewed ${stats.reviewed} card${stats.reviewed !== 1 ? "s" : ""}.`
            : "No cards are due for review today."}
        </p>
        {!user && (
          <p className="text-sm text-gray-500 dark:text-gray-400 mb-6">
            <Link href="/auth" className="text-emerald-600 dark:text-emerald-400 hover:underline">
              Sign in
            </Link>{" "}
            to use your favorites as your flashcard deck.
          </p>
        )}
        <div className="flex gap-3 justify-center flex-wrap">
          <button
            onClick={loadDeck}
            className="px-6 py-3 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg min-h-[44px]"
          >
            Study again
          </button>
          <Link
            href="/"
            className="px-6 py-3 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 min-h-[44px] flex items-center"
          >
            Home
          </Link>
        </div>
      </main>
    );
  }

  const current = deck[currentIndex];
  const nastaliq = current.script_variants?.nastaliq;
  const romanUrdu = current.script_variants?.roman_urdu;
  const definition = current.meanings?.[0]?.definition_en;

  return (
    <main className="max-w-lg mx-auto px-4 py-8">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <Link href="/" className="text-sm text-emerald-600 dark:text-emerald-400">← Home</Link>
        <span className="text-sm text-gray-500">
          {currentIndex + 1} / {deck.length} · {stats.due} due
        </span>
      </div>

      {/* Card */}
      <div className="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 shadow-sm overflow-hidden min-h-64 flex flex-col">
        <div className="flex-1 flex flex-col items-center justify-center p-8 text-center">
          {/* Front */}
          <p className="text-sm text-gray-400 mb-2 uppercase tracking-wide">English</p>
          <h2 className="text-4xl font-bold text-gray-900 dark:text-gray-100 capitalize mb-1">
            {current.word}
          </h2>
          {current.phonetic?.ipa && (
            <p className="text-gray-500 text-sm">{current.phonetic.ipa}</p>
          )}
          {current.learning?.emoji && (
            <p className="text-3xl mt-3">{current.learning.emoji}</p>
          )}

          {/* Back — revealed on tap */}
          {stage === "back" && (
            <div className="mt-6 pt-6 border-t border-gray-100 dark:border-gray-700 w-full">
              {nastaliq && (
                <>
                  <p className="text-sm text-gray-400 mb-1">Urdu</p>
                  <span dir="rtl" lang="ur" className="font-nastaliq text-3xl text-gray-900 dark:text-gray-100 block mb-2">
                    {nastaliq}
                  </span>
                </>
              )}
              {romanUrdu && (
                <p className="text-gray-500 text-sm mb-3 italic">{romanUrdu}</p>
              )}
              {definition && (
                <p className="text-sm text-gray-600 dark:text-gray-400">{definition}</p>
              )}
            </div>
          )}
        </div>

        {/* Action bar */}
        <div className="border-t border-gray-100 dark:border-gray-800 p-4">
          {stage === "front" ? (
            <button
              onClick={() => setStage("back")}
              className="w-full py-3 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg min-h-[44px]"
            >
              Show answer
            </button>
          ) : (
            <div className="grid grid-cols-4 gap-2">
              {[
                { label: "Again", q: 1, cls: "bg-red-100 dark:bg-red-900/40 text-red-700 dark:text-red-300 hover:bg-red-200 dark:hover:bg-red-800" },
                { label: "Hard", q: 2, cls: "bg-orange-100 dark:bg-orange-900/40 text-orange-700 dark:text-orange-300 hover:bg-orange-200" },
                { label: "Good", q: 4, cls: "bg-emerald-100 dark:bg-emerald-900/40 text-emerald-700 dark:text-emerald-300 hover:bg-emerald-200" },
                { label: "Easy", q: 5, cls: "bg-blue-100 dark:bg-blue-900/40 text-blue-700 dark:text-blue-300 hover:bg-blue-200" },
              ].map(({ label, q, cls }) => (
                <button
                  key={label}
                  onClick={() => handleQuality(q)}
                  className={`py-3 rounded-lg font-medium text-sm min-h-[44px] transition-colors ${cls}`}
                >
                  {label}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <p className="text-center text-xs text-gray-400 mt-4">
        Spaced repetition · SM-2 algorithm
      </p>
    </main>
  );
}
