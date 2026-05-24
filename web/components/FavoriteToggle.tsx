"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { addFavorite, getFavoriteStatus, removeFavorite } from "@/lib/api";
import { useAuth } from "@/lib/auth";

export default function FavoriteToggle({
  word,
  variant = "pill",
}: {
  word: string;
  variant?: "pill" | "icon";
}) {
  const router = useRouter();
  const { accessToken, isLoading: authLoading } = useAuth();
  const [favorited, setFavorited] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!accessToken) {
      setFavorited(false);
      return;
    }

    let cancelled = false;
    getFavoriteStatus(word, accessToken)
      .then((value) => {
        if (!cancelled) setFavorited(value);
      })
      .catch(() => {
        if (!cancelled) setFavorited(false);
      });

    return () => {
      cancelled = true;
    };
  }, [accessToken, word]);

  async function handleClick() {
    if (authLoading || busy) return;
    if (!accessToken) {
      router.push("/auth");
      return;
    }

    setBusy(true);
    try {
      if (favorited) {
        await removeFavorite(word, accessToken);
        setFavorited(false);
      } else {
        await addFavorite(word, accessToken);
        setFavorited(true);
      }
    } finally {
      setBusy(false);
    }
  }

  const icon = favorited ? "♥" : "♡";

  if (variant === "icon") {
    return (
      <button
        onClick={handleClick}
        disabled={busy || authLoading}
        aria-label={favorited ? "Remove from favorites" : "Save to favorites"}
        className={`inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-full border text-lg transition-colors ${
          favorited
            ? "border-rose-200 bg-rose-50 text-rose-600 dark:border-rose-900 dark:bg-rose-950/60 dark:text-rose-300"
            : "border-gray-200 bg-white text-gray-500 hover:border-rose-200 hover:text-rose-500 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:border-rose-900 dark:hover:text-rose-300"
        }`}
      >
        {icon}
      </button>
    );
  }

  return (
    <button
      onClick={handleClick}
      disabled={busy || authLoading}
      className={`inline-flex min-h-[44px] items-center gap-2 rounded-full border px-4 text-sm font-medium transition-colors ${
        favorited
          ? "border-rose-200 bg-rose-50 text-rose-600 dark:border-rose-900 dark:bg-rose-950/60 dark:text-rose-300"
          : "border-gray-200 bg-white text-gray-700 hover:border-rose-200 hover:text-rose-500 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-200 dark:hover:border-rose-900 dark:hover:text-rose-300"
      }`}
    >
      <span className="text-base leading-none">{icon}</span>
      <span>{favorited ? "Saved" : "Save"}</span>
    </button>
  );
}
