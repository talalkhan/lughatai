export const runtime = "edge";

import { Suspense } from "react";
import Link from "next/link";
import type { Metadata } from "next";
import SearchBar from "@/components/SearchBar";
import WordCard from "@/components/WordCard";
import WordCardSkeleton from "@/components/skeletons/WordCardSkeleton";
import { getWordOfTheDay } from "@/lib/api";
import {
  DEFAULT_OG_IMAGE,
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_TITLE,
  SITE_URL,
} from "@/lib/site";
import { WordData } from "@/lib/types";

export const metadata: Metadata = {
  title: SITE_TITLE,
  description: SITE_DESCRIPTION,
  alternates: { canonical: "/" },
  openGraph: {
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    url: SITE_URL,
    type: "website",
    images: [DEFAULT_OG_IMAGE],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [DEFAULT_OG_IMAGE],
  },
};

const CATEGORIES = [
  { label: "Daily Life", context: "daily" },
  { label: "Literature", context: "literature" },
  { label: "Poetry", context: "poetry" },
  { label: "Business", context: "business" },
  { label: "Science", context: "science" },
  { label: "Religion", context: "religion" },
];

const SAMPLE_WORDS = ["mercy", "sustain", "eloquent", "justice"];

async function WotdSection() {
  let word: WordData | null = null;
  try {
    word = await getWordOfTheDay();
  } catch {
    // no words yet
  }

  if (!word) {
    return (
      <p className="py-6 text-center text-sm text-gray-400 dark:text-gray-500">
        Word of the Day will appear once the dictionary has been populated.
      </p>
    );
  }

  return <WordCard variant="full" data={word} />;
}

export default function HomePage() {
  const homepageJsonLd = [
    {
      "@context": "https://schema.org",
      "@type": "WebSite",
      name: SITE_NAME,
      url: SITE_URL,
      description: SITE_DESCRIPTION,
      inLanguage: ["en", "ur"],
    },
    {
      "@context": "https://schema.org",
      "@type": "WebApplication",
      name: SITE_NAME,
      url: SITE_URL,
      applicationCategory: "ReferenceApplication",
      operatingSystem: "Any",
      description: SITE_DESCRIPTION,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
  ];

  return (
    <main>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(homepageJsonLd) }}
      />

      {/* Hero */}
      <section className="mx-auto max-w-2xl px-4 pb-16 pt-20 text-center sm:pt-28">
        <p className="mb-5 text-xs font-semibold uppercase tracking-[0.3em] text-emerald-700 dark:text-emerald-400">
          English · Urdu Dictionary
        </p>
        <h1 className="text-4xl font-bold tracking-tight text-gray-950 dark:text-white sm:text-5xl">
          Find the right Urdu word,{" "}
          <span className="text-emerald-600 dark:text-emerald-400">every time.</span>
        </h1>
        <p className="mt-4 text-base text-gray-500 dark:text-gray-400 sm:text-lg">
          Meanings, examples, and pronunciation — without the clutter.
        </p>

        <div className="mt-8">
          <SearchBar autoFocus />
        </div>

        <div className="mt-4 flex flex-wrap justify-center gap-2">
          {SAMPLE_WORDS.map((word) => (
            <Link
              key={word}
              href={`/word/${word}`}
              className="inline-flex min-h-[36px] items-center rounded-full border border-gray-200 bg-white px-3 text-sm text-gray-600 transition-colors hover:border-emerald-300 hover:text-emerald-700 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-400 dark:hover:border-emerald-700 dark:hover:text-emerald-300"
            >
              {word}
            </Link>
          ))}
        </div>
      </section>

      {/* Word of the Day */}
      <section className="mx-auto max-w-2xl px-4 pb-16">
        <div className="mb-5 flex items-center justify-between">
          <h2 className="text-xs font-semibold uppercase tracking-[0.3em] text-gray-400 dark:text-gray-500">
            Word of the Day
          </h2>
          <Link
            href="/browse"
            className="text-sm font-medium text-emerald-700 hover:text-emerald-800 dark:text-emerald-400 dark:hover:text-emerald-300"
          >
            Browse all →
          </Link>
        </div>
        <Suspense fallback={<WordCardSkeleton />}>
          <WotdSection />
        </Suspense>
      </section>

      {/* Topic chips */}
      <section className="mx-auto max-w-2xl px-4 pb-24 text-center">
        <p className="mb-4 text-xs font-semibold uppercase tracking-[0.3em] text-gray-400 dark:text-gray-500">
          Explore by topic
        </p>
        <div className="flex flex-wrap justify-center gap-2">
          {CATEGORIES.map((cat) => (
            <Link
              key={cat.context}
              href={`/browse?context=${cat.context}`}
              className="inline-flex min-h-[36px] items-center rounded-full border border-gray-200 bg-white px-3 text-sm text-gray-600 transition-colors hover:border-emerald-300 hover:text-emerald-700 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-400 dark:hover:border-emerald-700 dark:hover:text-emerald-300"
            >
              {cat.label}
            </Link>
          ))}
        </div>
      </section>
    </main>
  );
}
