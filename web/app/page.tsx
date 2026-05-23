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
    <main className="min-h-screen">
      {/* Hero */}
      <section className="bg-gradient-to-b from-indigo-50 to-white dark:from-indigo-950 dark:to-gray-950 px-4 py-20">
        <div className="max-w-3xl mx-auto text-center">
          <h1 className="text-4xl sm:text-5xl font-bold text-gray-900 dark:text-gray-100 mb-3">
            LughatAI
          </h1>
          <p className="text-lg text-gray-600 dark:text-gray-400 mb-10">
            The richest Urdu dictionary, powered by AI
          </p>
          <SearchBar autoFocus />
        </div>
      </section>

      <div className="max-w-4xl mx-auto px-4 py-12 space-y-14">
        {/* Word of the Day */}
        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-4">
            📅 Word of the Day
          </h2>
          <Suspense fallback={<WordCardSkeleton />}>
            <WotdSection />
          </Suspense>
        </section>

        {/* Browse by Category */}
        <section>
          <h2 className="text-xl font-semibold text-gray-900 dark:text-gray-100 mb-4">
            Browse by Category
          </h2>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {CATEGORIES.map((cat) => (
              <Link
                key={cat.context}
                href={`/browse?context=${cat.context}`}
                className="flex items-center gap-2 p-4 rounded-2xl border border-gray-200
                           dark:border-gray-700 bg-white dark:bg-gray-900
                           hover:border-indigo-300 dark:hover:border-indigo-600
                           hover:shadow-sm transition-all min-h-[44px]"
              >
                <span className="text-xl">{cat.emoji}</span>
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
