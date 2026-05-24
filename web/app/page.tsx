import { Suspense } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import SearchBar from "@/components/SearchBar";
import WordCard from "@/components/WordCard";
import WordCardSkeleton from "@/components/skeletons/WordCardSkeleton";
import { getWordOfTheDay } from "@/lib/api";
import { WordData } from "@/lib/types";

export const metadata: Metadata = {
  title: "LughatAI — AI-Powered English to Urdu Dictionary",
  description:
    "The richest English-to-Urdu dictionary, powered by AI. Discover translations, examples, poetry, and deep cultural context.",
  openGraph: {
    title: "LughatAI — AI-Powered English to Urdu Dictionary",
    description: "The richest English-to-Urdu dictionary, powered by AI.",
    type: "website",
  },
};

const CATEGORIES = [
  { label: "Religion", context: "religion", emoji: "🕌" },
  { label: "Literature", context: "literature", emoji: "📚" },
  { label: "Poetry", context: "poetry", emoji: "✍️" },
  { label: "Business", context: "business", emoji: "💼" },
  { label: "Science", context: "science", emoji: "🔬" },
  { label: "Philosophy", context: "philosophy", emoji: "🧠" },
  { label: "Medicine", context: "medicine", emoji: "🏥" },
  { label: "Daily Life", context: "daily", emoji: "🌟" },
];

const QUICK_LINKS = [
  { label: "Browse Library", href: "/browse", tone: "bg-indigo-600 text-white hover:bg-indigo-700" },
  { label: "Flashcards", href: "/flashcards", tone: "bg-white text-gray-800 hover:bg-gray-100 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800" },
  { label: "Quiz", href: "/quiz", tone: "bg-white text-gray-800 hover:bg-gray-100 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800" },
  { label: "Saved Words", href: "/favorites", tone: "bg-white text-gray-800 hover:bg-gray-100 dark:bg-gray-900 dark:text-gray-100 dark:hover:bg-gray-800" },
];

async function WotdSection() {
  let word: WordData | null = null;
  try {
    word = await getWordOfTheDay();
  } catch {
    // No words yet — section stays empty
  }

  if (!word) {
    return (
      <div className="text-center py-8 text-gray-500 dark:text-gray-400 text-sm">
        Word of the Day will appear once the dictionary has been populated.
      </div>
    );
  }

  return <WordCard variant="full" data={word} />;
}

export default function HomePage() {
  return (
    <main>
      {/* Hero */}
      <section className="px-4 pt-10 pb-8 sm:pt-12">
        <div className="mx-auto max-w-5xl rounded-[2rem] border border-indigo-100 bg-gradient-to-br from-white via-indigo-50/70 to-sky-50/80 px-6 py-8 shadow-[0_30px_80px_-50px_rgba(79,70,229,0.55)] dark:border-indigo-900/60 dark:from-gray-950 dark:via-indigo-950/40 dark:to-slate-950 sm:px-8 sm:py-10">
          <div className="mx-auto max-w-3xl text-center">
            <p className="mb-3 text-xs font-semibold uppercase tracking-[0.35em] text-indigo-600 dark:text-indigo-300">
              Cache-first Urdu dictionary
            </p>
            <h1 className="mb-3 text-4xl font-bold tracking-tight text-gray-950 dark:text-white sm:text-5xl">
              English to Urdu, with context that actually helps you remember.
            </h1>
            <p className="mx-auto mb-8 max-w-2xl text-base text-gray-600 dark:text-gray-300 sm:text-lg">
              Search any word, see nuanced meanings, examples, poetry, proverbs, and memory cues in one place.
            </p>
            <SearchBar autoFocus />

            <div className="mt-5 flex flex-wrap items-center justify-center gap-3">
              {QUICK_LINKS.map((link) => (
                <Link
                  key={link.href}
                  href={link.href}
                  className={`inline-flex min-h-[44px] items-center rounded-full px-4 text-sm font-medium transition-colors ${link.tone}`}
                >
                  {link.label}
                </Link>
              ))}
            </div>
          </div>
        </div>
      </section>

      <div className="mx-auto max-w-5xl px-4 py-8 space-y-10 sm:py-10">
        {/* Word of the Day */}
        <section>
          <div className="mb-4 flex items-end justify-between gap-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-[0.25em] text-gray-500 dark:text-gray-400">
                Today&apos;s anchor word
              </p>
              <h2 className="text-2xl font-semibold text-gray-900 dark:text-gray-100">
                Word of the Day
              </h2>
            </div>
            <Link
              href="/browse"
              className="hidden text-sm font-medium text-indigo-600 hover:text-indigo-700 dark:text-indigo-300 dark:hover:text-indigo-200 sm:inline"
            >
              Explore the full library →
            </Link>
          </div>
          <Suspense fallback={<WordCardSkeleton />}>
            <WotdSection />
          </Suspense>
        </section>

        {/* Browse by Category */}
        <section>
          <div className="mb-4">
            <p className="text-xs font-semibold uppercase tracking-[0.25em] text-gray-500 dark:text-gray-400">
              Explore by context
            </p>
            <h2 className="text-2xl font-semibold text-gray-900 dark:text-gray-100">
              Browse by Category
            </h2>
          </div>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {CATEGORIES.map((cat) => (
              <Link
                key={cat.context}
                href={`/browse?context=${cat.context}`}
                className="flex min-h-[88px] items-center gap-3 rounded-2xl border border-gray-200 bg-white p-4 transition-all hover:-translate-y-0.5 hover:border-indigo-300 hover:shadow-md dark:border-gray-700 dark:bg-gray-900 dark:hover:border-indigo-600"
              >
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-indigo-50 text-2xl dark:bg-indigo-950/70">
                  {cat.emoji}
                </span>
                <span className="font-medium text-sm text-gray-700 dark:text-gray-300">
                  {cat.label}
                </span>
              </Link>
            ))}
          </div>
        </section>
      </div>
    </main>
  );
}
