import type { Metadata } from "next";
import { Suspense } from "react";
import BrowseClient from "./BrowseClient";
import WordCardSkeleton from "@/components/skeletons/WordCardSkeleton";

export const metadata: Metadata = {
  title: "Browse English Words | UrduMeaning",
  description: "Browse English words and meanings in Urdu by difficulty, CEFR level, or category.",
  alternates: {
    canonical: "/browse",
  },
};

export default function BrowsePage() {
  return (
    <main className="mx-auto max-w-6xl px-4 py-6 sm:py-8">
      <Suspense fallback={
        <div className="grid sm:grid-cols-2 gap-4">
          {Array.from({ length: 6 }).map((_, i) => <WordCardSkeleton key={i} />)}
        </div>
      }>
        <BrowseClient />
      </Suspense>
    </main>
  );
}
