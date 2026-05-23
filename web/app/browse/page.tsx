import { Suspense } from "react";
import BrowseClient from "./BrowseClient";
import WordCardSkeleton from "@/components/skeletons/WordCardSkeleton";

export const metadata = {
  title: "Browse Words | LughatAI",
  description: "Browse English words by difficulty, CEFR level, or category.",
};

export default function BrowsePage() {
  return (
    <main className="max-w-4xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100 mb-6">Browse Words</h1>
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
