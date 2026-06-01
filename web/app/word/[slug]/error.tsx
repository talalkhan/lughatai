"use client";

import Link from "next/link";

export default function WordError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  const isTimeout =
    error.message?.toLowerCase().includes("timed out") ||
    error.message?.toLowerCase().includes("unavailable");

  return (
    <main className="min-h-[60vh] flex items-center justify-center px-4">
      <div className="max-w-md w-full text-center space-y-5">
        <div className="text-6xl">{isTimeout ? "⏳" : "⚠️"}</div>

        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">
          {isTimeout
            ? "Still generating…"
            : "Something went wrong"}
        </h1>

        <p className="text-gray-600 dark:text-gray-400">
          {isTimeout
            ? "AI is building a full Urdu definition for this word. It may take a moment on the first visit. Try again shortly."
            : "An unexpected error occurred loading this word. Please try again."}
        </p>

        <div className="flex flex-col sm:flex-row gap-3 justify-center pt-2">
          <button
            onClick={reset}
            className="px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-medium transition-colors min-h-[44px]"
          >
            Try again
          </button>
          <Link
            href="/"
            className="px-6 py-3 border border-gray-300 dark:border-gray-600 text-gray-700 dark:text-gray-300 hover:bg-gray-100 dark:hover:bg-gray-800 rounded-xl font-medium transition-colors min-h-[44px] inline-flex items-center justify-center"
          >
            Search another word
          </Link>
        </div>
      </div>
    </main>
  );
}
