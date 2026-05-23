"use client";

import { useRef, useState } from "react";

interface Props {
  url: string | null | undefined;
  lang: "EN" | "UR";
}

export default function AudioPlayer({ url, lang }: Props) {
  const audioRef = useRef<HTMLAudioElement>(null);
  const [playing, setPlaying] = useState(false);

  async function handlePlay() {
    if (!url || !audioRef.current) return;
    if (playing) {
      audioRef.current.pause();
      audioRef.current.currentTime = 0;
      setPlaying(false);
    } else {
      try {
        setPlaying(true);
        await audioRef.current.play();
      } catch {
        setPlaying(false);
      }
    }
  }

  const disabled = !url;

  return (
    <>
      {url && <audio ref={audioRef} src={url} onEnded={() => setPlaying(false)} preload="none" />}
      <button
        onClick={handlePlay}
        disabled={disabled}
        title={disabled ? "Audio coming soon" : `Play ${lang} pronunciation`}
        className={`inline-flex items-center gap-1.5 px-3 py-2 rounded-lg text-sm font-medium
          min-w-[44px] min-h-[44px] transition-colors
          ${disabled
            ? "bg-gray-100 text-gray-400 dark:bg-gray-800 dark:text-gray-600 cursor-not-allowed"
            : "bg-indigo-100 text-indigo-700 hover:bg-indigo-200 dark:bg-indigo-900 dark:text-indigo-300 dark:hover:bg-indigo-800 cursor-pointer"
          }`}
        aria-label={`${playing ? "Stop" : "Play"} ${lang} audio`}
      >
        {playing ? "⏹" : "▶"} {lang}
      </button>
    </>
  );
}
