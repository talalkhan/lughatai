"use client";

import { useWordCache } from "@/lib/hooks/useWordCache";
import { WordData } from "@/lib/types";

/**
 * Invisible client component that saves the word to IndexedDB for offline access.
 * Rendered inside the SSR word detail page.
 */
export default function WordCacheWriter({ word }: { word: WordData }) {
  useWordCache(word);
  return null;
}
