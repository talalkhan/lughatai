"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { getRandomWord } from "@/lib/api";
import { QuizQuestion, WordData } from "@/lib/types";

type Mode = "en_to_ur" | "ur_to_en";
type Phase = "loading" | "question" | "feedback" | "done";

function shuffle<T>(arr: T[]): T[] {
  return [...arr].sort(() => Math.random() - 0.5);
}

function buildQuestion(correct: WordData, distractors: WordData[], mode: Mode): QuizQuestion | null {
  const nastaliq = correct.script_variants?.nastaliq;
  const primary = correct.meanings?.[0]?.translations?.primary;

  if (!nastaliq || !primary) return null;

  const distractorChoices = distractors
    .map(d =>
      mode === "en_to_ur"
        ? d.script_variants?.nastaliq
        : d.word
    )
    .filter((c): c is string => !!c)
    .slice(0, 3);

  if (distractorChoices.length < 3) return null;

  const correctAnswer = mode === "en_to_ur" ? nastaliq : correct.word;
  const choices = shuffle([correctAnswer, ...distractorChoices]);

  return {
    word: correct.word,
    urdu: nastaliq,
    correct: correctAnswer,
    choices,
    mode,
  };
}

const QUIZ_LENGTH = 10;

export default function QuizPage() {
  const [mode, setMode] = useState<Mode>("en_to_ur");
  const [questions, setQuestions] = useState<QuizQuestion[]>([]);
  const [current, setCurrent] = useState(0);
  const [phase, setPhase] = useState<Phase>("loading");
  const [selected, setSelected] = useState<string | null>(null);
  const [score, setScore] = useState(0);
  const [streak, setStreak] = useState(0);

  const loadQuiz = useCallback(async (quizMode: Mode) => {
    setPhase("loading");
    setScore(0);
    setStreak(0);
    setCurrent(0);
    setSelected(null);

    // Fetch enough random words for questions + distractors
    const fetched = await Promise.allSettled(
      Array.from({ length: QUIZ_LENGTH + 3 }, () => getRandomWord())
    );
    const words = fetched
      .filter((r): r is PromiseFulfilledResult<WordData> => r.status === "fulfilled")
      .map(r => r.value)
      .filter(w => w.script_variants?.nastaliq && w.meanings?.[0]?.translations?.primary);

    if (words.length < 4) {
      setPhase("done");
      return;
    }

    const qs: QuizQuestion[] = [];
    for (let i = 0; i < Math.min(words.length, QUIZ_LENGTH); i++) {
      const distractors = words.filter((_, j) => j !== i);
      const q = buildQuestion(words[i], distractors, quizMode);
      if (q) qs.push(q);
    }

    setQuestions(qs);
    setPhase(qs.length > 0 ? "question" : "done");
  }, []);

  useEffect(() => {
    loadQuiz(mode);
  }, [loadQuiz, mode]);

  function handleAnswer(choice: string) {
    if (phase !== "question") return;
    setSelected(choice);
    setPhase("feedback");

    const q = questions[current];
    const correct = choice === q.correct;
    if (correct) {
      setScore(s => s + 1);
      setStreak(s => s + 1);
    } else {
      setStreak(0);
    }
  }

  function handleNext() {
    if (current + 1 >= questions.length) {
      setPhase("done");
    } else {
      setCurrent(c => c + 1);
      setSelected(null);
      setPhase("question");
    }
  }

  // ── Screens ───────────────────────────────────────────────────────────────

  if (phase === "loading") {
    return (
      <main className="max-w-lg mx-auto px-4 py-12 text-center">
        <div className="animate-pulse space-y-4">
          <div className="h-8 bg-gray-200 dark:bg-gray-800 rounded w-1/2 mx-auto" />
          <div className="h-40 bg-gray-200 dark:bg-gray-800 rounded-xl" />
          <div className="grid grid-cols-2 gap-3">
            {[0, 1, 2, 3].map(i => (
              <div key={i} className="h-16 bg-gray-200 dark:bg-gray-800 rounded-lg" />
            ))}
          </div>
        </div>
      </main>
    );
  }

  if (phase === "done") {
    const pct = questions.length > 0 ? Math.round((score / questions.length) * 100) : 0;
    return (
      <main className="max-w-lg mx-auto px-4 py-16 text-center">
        <p className="text-5xl mb-4">{pct >= 80 ? "🏆" : pct >= 50 ? "👍" : "📖"}</p>
        <h1 className="text-2xl font-bold mb-2">Quiz complete!</h1>
        <p className="text-5xl font-bold text-emerald-600 dark:text-emerald-400 my-4">
          {score} / {questions.length}
        </p>
        <p className="text-gray-500 dark:text-gray-400 mb-8">{pct}% correct</p>
        <div className="flex gap-3 justify-center flex-wrap">
          <button
            onClick={() => loadQuiz(mode)}
            className="px-6 py-3 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg min-h-[44px]"
          >
            Play again
          </button>
          <button
            onClick={() => setMode(m => m === "en_to_ur" ? "ur_to_en" : "en_to_ur")}
            className="px-6 py-3 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 min-h-[44px]"
          >
            Switch mode
          </button>
          <Link
            href="/"
            className="px-6 py-3 border border-gray-300 dark:border-gray-600 rounded-lg hover:bg-gray-50 dark:hover:bg-gray-800 min-h-[44px] flex items-center"
          >
            Home
          </Link>
        </div>
      </main>
    );
  }

  const q = questions[current];
  const isCorrect = selected === q.correct;

  return (
    <main className="max-w-lg mx-auto px-4 py-8">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <Link href="/" className="text-sm text-emerald-600 dark:text-emerald-400">← Home</Link>
        <div className="flex items-center gap-4 text-sm text-gray-500">
          {streak >= 3 && <span>🔥 {streak}</span>}
          <span>{current + 1} / {questions.length}</span>
          <span className="text-emerald-600 dark:text-emerald-400 font-semibold">{score} ✓</span>
        </div>
      </div>

      {/* Mode toggle */}
      <div className="flex rounded-lg border border-gray-200 dark:border-gray-700 mb-6 overflow-hidden text-sm">
        {(["en_to_ur", "ur_to_en"] as Mode[]).map(m => (
          <button
            key={m}
            onClick={() => setMode(m)}
            className={`flex-1 py-2 transition-colors min-h-[44px] ${
              mode === m
                ? "bg-emerald-600 text-white"
                : "bg-white dark:bg-gray-900 text-gray-600 dark:text-gray-400"
            }`}
          >
            {m === "en_to_ur" ? "English → Urdu" : "Urdu → English"}
          </button>
        ))}
      </div>

      {/* Progress bar */}
      <div className="w-full bg-gray-200 dark:bg-gray-800 rounded-full h-1.5 mb-6">
        <div
          className="bg-emerald-500 h-1.5 rounded-full transition-all"
          style={{ width: `${((current) / questions.length) * 100}%` }}
        />
      </div>

      {/* Question */}
      <div className="rounded-2xl border border-gray-200 dark:border-gray-700 bg-white dark:bg-gray-900 p-8 text-center mb-6">
        <p className="text-xs text-gray-400 uppercase tracking-wide mb-3">
          {mode === "en_to_ur" ? "What is the Urdu translation of:" : "What does this mean in English:"}
        </p>
        {mode === "en_to_ur" ? (
          <h2 className="text-4xl font-bold capitalize">{q.word}</h2>
        ) : (
          <span dir="rtl" lang="ur" className="font-nastaliq text-4xl block">
            {q.urdu}
          </span>
        )}
      </div>

      {/* Choices */}
      <div className="grid grid-cols-2 gap-3 mb-6">
        {q.choices.map(choice => {
          let cls =
            "p-4 rounded-xl border-2 text-center min-h-[64px] flex items-center justify-center transition-colors ";

          if (phase === "feedback") {
            if (choice === q.correct) {
              cls += "border-emerald-500 bg-emerald-50 dark:bg-emerald-900/30 text-emerald-700 dark:text-emerald-300";
            } else if (choice === selected) {
              cls += "border-red-400 bg-red-50 dark:bg-red-900/30 text-red-700 dark:text-red-300";
            } else {
              cls += "border-gray-200 dark:border-gray-700 text-gray-400";
            }
          } else {
            cls += "border-gray-200 dark:border-gray-700 hover:border-emerald-400 hover:bg-emerald-50 dark:hover:bg-emerald-900/20 cursor-pointer";
          }

          return (
            <button
              key={choice}
              onClick={() => handleAnswer(choice)}
              disabled={phase === "feedback"}
              className={cls}
            >
              {mode === "en_to_ur" ? (
                <span dir="rtl" lang="ur" className="font-nastaliq text-2xl">{choice}</span>
              ) : (
                <span className="font-medium capitalize">{choice}</span>
              )}
            </button>
          );
        })}
      </div>

      {/* Feedback */}
      {phase === "feedback" && (
        <div className={`rounded-xl p-4 mb-4 text-center ${
          isCorrect
            ? "bg-emerald-50 dark:bg-emerald-900/20 border border-emerald-200 dark:border-emerald-800"
            : "bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800"
        }`}>
          <p className={`font-semibold mb-1 ${isCorrect ? "text-emerald-700 dark:text-emerald-300" : "text-red-700 dark:text-red-300"}`}>
            {isCorrect ? "Correct! 🎉" : "Not quite"}
          </p>
          {!isCorrect && (
            <p className="text-sm text-gray-600 dark:text-gray-400">
              Correct answer:{" "}
              {mode === "en_to_ur" ? (
                <span dir="rtl" lang="ur" className="font-nastaliq">{q.correct}</span>
              ) : (
                <strong>{q.correct}</strong>
              )}
            </p>
          )}
          <Link
            href={`/word/${q.word}`}
            className="text-xs text-emerald-600 dark:text-emerald-400 hover:underline mt-1 block"
          >
            See full definition →
          </Link>
        </div>
      )}

      {phase === "feedback" && (
        <button
          onClick={handleNext}
          className="w-full py-3 bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded-lg min-h-[44px]"
        >
          {current + 1 >= questions.length ? "See results" : "Next question"}
        </button>
      )}
    </main>
  );
}
