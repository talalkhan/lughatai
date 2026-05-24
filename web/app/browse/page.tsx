import { Suspense } from "react";
import BrowseClient from "./BrowseClient";
import WordCardSkeleton from "@/components/skeletons/WordCardSkeleton";

export const metadata = {
  title: "Browse Words | UrduMeaning",
  description: "Browse English words by difficulty, CEFR level, or category.",
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
