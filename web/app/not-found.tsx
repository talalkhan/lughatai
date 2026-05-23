import Link from "next/link";

export default function NotFound() {
  return (
    <main className="min-h-screen flex items-center justify-center px-4">
      <div className="max-w-md w-full text-center space-y-4">
        <div className="text-6xl">📭</div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-gray-100">Page Not Found</h1>
        <p className="text-gray-600 dark:text-gray-400">
          This page doesn&apos;t exist. Try searching for a word.
        </p>
        <Link
          href="/"
          className="inline-block px-6 py-3 bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl font-medium transition-colors"
        >
          Go home
        </Link>
      </div>
    </main>
  );
}
