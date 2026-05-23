export default function WordDetailSkeleton() {
  return (
    <div className="max-w-4xl mx-auto px-4 py-8 animate-pulse">
      <div className="h-10 w-48 bg-gray-200 dark:bg-gray-700 rounded mb-2" />
      <div className="h-5 w-32 bg-gray-200 dark:bg-gray-700 rounded mb-6" />
      <div className="h-12 w-40 bg-gray-200 dark:bg-gray-700 rounded mb-8" />
      {[1, 2, 3].map((i) => (
        <div key={i} className="mb-8 p-6 bg-white dark:bg-gray-900 rounded-2xl border border-gray-200 dark:border-gray-700">
          <div className="h-6 w-20 bg-gray-200 dark:bg-gray-700 rounded mb-4" />
          <div className="h-4 w-full bg-gray-100 dark:bg-gray-800 rounded mb-2" />
          <div className="h-4 w-3/4 bg-gray-100 dark:bg-gray-800 rounded mb-2" />
          <div className="h-4 w-5/6 bg-gray-100 dark:bg-gray-800 rounded" />
        </div>
      ))}
    </div>
  );
}
