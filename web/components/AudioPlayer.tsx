"use client";

import { useRef, useState } from "react";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:5000";

interface Props {
  url: string | null | undefined;
  lang: "EN" | "UR";
  word: string;
}

export default function AudioPlayer({ url, lang, word }: Props) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);
  const [loading, setLoading] = useState(false);
  // Track whether we've already set audio.src so subsequent plays skip re-loading
  const srcSet = useRef(false);

  async function handlePlay() {
    const audio = audioRef.current;
    if (!audio) return;

    if (playing) {
      audio.pause();
      audio.currentTime = 0;
      setPlaying(false);
      return;
    }

    // Set src lazily on first play.
    // Media elements bypass CORS, so pointing directly at the API endpoint is safe —
    // the browser follows the 302 redirect to Blob/CDN without needing CORS headers.
    if (!srcSet.current) {
      audio.src =
        url ??
        `${API_URL}/api/word/${encodeURIComponent(word)}/audio?lang=${lang.toLowerCase()}`;
      audio.load();
      srcSet.current = true;
    }

    setLoading(true);
    try {
      await audio.play();
      setPlaying(true);
    } catch {
      // AbortError on rapid double-tap; NotAllowedError shouldn't happen (user gesture)
    } finally {
      setLoading(false);
    }
  }

  return (
    <>
      <audio ref={audioRef} onEnded={() => setPlaying(false)} preload="none" />
      <button
        onClick={handlePlay}
        disabled={loading}
        title={loading ? "Generating audio…" : `Play ${lang} pronunciation`}
        className={`inline-flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium
          min-w-[44px] min-h-[44px] transition-colors
          ${loading
            ? "bg-gray-100 text-gray-400 dark:bg-gray-800 dark:text-gray-600 cursor-wait"
            : "bg-indigo-100 text-indigo-700 hover:bg-indigo-200 dark:bg-indigo-900 dark:text-indigo-300 dark:hover:bg-indigo-800 cursor-pointer"
          }`}
        aria-label={`${playing ? "Stop" : "Play"} ${lang} audio`}
      >
        {loading ? "…" : playing ? "⏹" : "▶"} {lang}
      </button>
    </>
  );
}
