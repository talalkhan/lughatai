import Link from "next/link";
import { WordData, WordSummary } from "@/lib/types";

function DifficultyBadge({ difficulty }: { difficulty?: string }) {
  const colors: Record<string, string> = {
    beginner: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
    intermediate: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
    advanced: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
    expert: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
  };
  if (!difficulty) return null;
  return (
    <span className={`text-xs px-2 py-0.5 rounded-full font-medium ${colors[difficulty] ?? "bg-gray-100 text-gray-700"}`}>
      {difficulty}
    </span>
  );
}

interface CompactProps {
  variant: "compact";
  data: WordSummary;
}

interface FullProps {
  variant: "full";
  data: WordData;
}

type Props = CompactProps | FullProps;

export default function WordCard(props: Props) {
  const { variant, data } = props;

  if (variant === "compact") {
    const w = data as WordSummary;
    return (
      <Link
        href={`/word/${encodeURIComponent(w.word.toLowerCase())}`}
        className="block p-5 rounded-2xl border border-gray-200 dark:border-gray-700
                   hover:border-indigo-300 dark:hover:border-indigo-600
                   bg-white dark:bg-gray-900 transition-all hover:shadow-md"
      >
        <div className="flex items-start justify-between gap-3">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 mb-1">
              {w.emoji && <span className="text-xl">{w.emoji}</span>}
              <h3 className="font-semibold text-gray-900 dark:text-gray-100 truncate">{w.word}</h3>
              <DifficultyBadge difficulty={w.difficulty} />
            </div>
            {w.urdu && (
              <p dir="rtl" lang="ur" className="font-nastaliq text-xl text-indigo-700 dark:text-indigo-300 mb-2">
                {w.urdu}
              </p>
            )}
            {w.definitionEn && (
              <p className="text-sm text-gray-500 dark:text-gray-400 line-clamp-2">{w.definitionEn}</p>
            )}
          </div>
        </div>
      </Link>
    );
  }

  const w = data as WordData;
  const primaryMeaning = w.meanings?.[0];
  const urdu = w.script_variants?.nastaliq;

  return (
    <Link
      href={`/word/${encodeURIComponent(w.word.toLowerCase())}`}
      className="block p-5 rounded-2xl border border-gray-200 dark:border-gray-700
                 hover:border-indigo-300 dark:hover:border-indigo-600
                 bg-white dark:bg-gray-900 transition-all hover:shadow-md"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap mb-1">
            {w.learning?.emoji && <span className="text-xl">{w.learning.emoji}</span>}
            <h3 className="font-semibold text-gray-900 dark:text-gray-100">{w.word}</h3>
            <DifficultyBadge difficulty={w.learning?.difficulty} />
            {w.learning?.cefr_level && (
              <span className="text-xs px-2 py-0.5 rounded-full bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200">
                {w.learning.cefr_level}
              </span>
            )}
          </div>

          {urdu && (
            <p dir="rtl" lang="ur" className="font-nastaliq text-2xl text-indigo-700 dark:text-indigo-300 mb-2">
              {urdu}
            </p>
          )}

          {w.learning?.contexts && w.learning.contexts.length > 0 && (
            <div className="flex flex-wrap gap-1 mb-2">
              {w.learning.contexts.slice(0, 4).map((ctx) => (
                <span key={ctx} className="text-xs px-2 py-0.5 rounded-full bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400">
                  {ctx}
                </span>
              ))}
            </div>
          )}

          {primaryMeaning?.definition_en && (
            <p className="text-sm text-gray-500 dark:text-gray-400 line-clamp-2">
              {primaryMeaning.definition_en}
            </p>
          )}
        </div>
      </div>
    </Link>
  );
}
