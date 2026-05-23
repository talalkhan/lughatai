"use client";

import { useEffect, useState } from "react";
import WordDetailSkeleton from "@/components/skeletons/WordDetailSkeleton";

export default function Loading() {
  // After 1.5 s assume it's a cache miss and the AI is generating
  const [isGenerating, setIsGenerating] = useState(false);

  useEffect(() => {
    const t = setTimeout(() => setIsGenerating(true), 1500);
    return () => clearTimeout(t);
  }, []);

  return (
    <div className="max-w-4xl mx-auto px-4 py-8">
      <div
        className={`mb-6 flex items-center gap-4 p-4 rounded-2xl border transition-all duration-500
          ${isGenerating
            ? "bg-indigo-50 dark:bg-indigo-950 border-indigo-200 dark:border-indigo-800"
            : "bg-gray-50 dark:bg-gray-800/50 border-gray-200 dark:border-gray-700"
          }`}
      >
        <span
          className={`inline-block w-5 h-5 border-2 rounded-full animate-spin flex-shrink-0 transition-colors duration-500
            ${isGenerating
              ? "border-indigo-600 dark:border-indigo-400 border-t-transparent"
              : "border-gray-400 dark:border-gray-500 border-t-transparent"
            }`}
        />
        <div>
          <p
            className={`text-sm font-medium transition-colors duration-500
              ${isGenerating
                ? "text-indigo-900 dark:text-indigo-100"
                : "text-gray-600 dark:text-gray-300"
              }`}
          >
            {isGenerating ? "Generating AI translation…" : "Loading…"}
          </p>
          {isGenerating && (
            <p className="text-xs text-indigo-600 dark:text-indigo-400 mt-0.5">
              This is a new word — Claude is building a full Urdu definition
            </p>
          )}
        </div>
      </div>

      <WordDetailSkeleton />
    </div>
  );
}
