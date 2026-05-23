export default function WordCardSkeleton() {
  return (
    <div className="p-5 rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 animate-pulse">
      <div className="flex items-center gap-2 mb-3">
        <div className="h-5 w-5 bg-gray-200 dark:bg-gray-700 rounded" />
        <div className="h-5 w-24 bg-gray-200 dark:bg-gray-700 rounded" />
        <div className="h-4 w-16 bg-gray-200 dark:bg-gray-700 rounded-full" />
      </div>
      <div className="h-8 w-32 bg-gray-200 dark:bg-gray-700 rounded mb-3" />
      <div className="h-3 w-full bg-gray-100 dark:bg-gray-800 rounded mb-1" />
      <div className="h-3 w-3/4 bg-gray-100 dark:bg-gray-800 rounded" />
    </div>
  );
}
