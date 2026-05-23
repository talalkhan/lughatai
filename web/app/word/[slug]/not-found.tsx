import Link from "next/link";
import SearchBar from "@/components/SearchBar";

export default function WordNotFound() {
  return (
    <main className="min-h-screen flex items-center justify-center px-4">
      <div className="max-w-md w-full text-center space-y-6">
        <div className="text-6xl">🔍</div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Word Not Found</h1>
        <p className="text-gray-600 dark:text-gray-400">
          We couldn&apos;t find that word. Try a different spelling, or search below.
        </p>
        <SearchBar autoFocus />
        <Link href="/" className="inline-block text-indigo-600 dark:text-indigo-400 hover:underline text-sm">
          ← Back to home
        </Link>
      </div>
    </main>
  );
}
