"use client";

import { useCallback, useEffect, useRef } from "react";
import { WordData } from "@/lib/types";

const DB_NAME = "lughatai";
const DB_VERSION = 1;
const STORE = "words";

function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains(STORE)) {
        const store = db.createObjectStore(STORE, { keyPath: "word" });
        store.createIndex("saved_at", "saved_at");
      }
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function putWord(data: WordData): Promise<void> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    tx.objectStore(STORE).put({ ...data, saved_at: Date.now() });
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

async function getWord(word: string): Promise<WordData | null> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const req = db.transaction(STORE, "readonly").objectStore(STORE).get(word);
    req.onsuccess = () => resolve(req.result ?? null);
    req.onerror = () => reject(req.error);
  });
}

async function getAllWords(): Promise<WordData[]> {
  const db = await openDB();
  return new Promise((resolve, reject) => {
    const req = db.transaction(STORE, "readonly").objectStore(STORE).getAll();
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

async function deleteOldWords(maxCount: number): Promise<void> {
  const db = await openDB();
  const all = await getAllWords();
  if (all.length <= maxCount) return;

  // Sort by saved_at ascending, remove oldest
  const sorted = all.sort((a, b) => (a as any).saved_at - (b as any).saved_at);
  const toDelete = sorted.slice(0, all.length - maxCount).map(w => w.word);

  return new Promise((resolve, reject) => {
    const tx = db.transaction(STORE, "readwrite");
    const store = tx.objectStore(STORE);
    toDelete.forEach(w => store.delete(w));
    tx.oncomplete = () => resolve();
    tx.onerror = () => reject(tx.error);
  });
}

/**
 * Hook: saves a WordData to IndexedDB when the word loads.
 * Keeps the 500 most recently cached words.
 * Used by the word detail page for offline access.
 */
export function useWordCache(data: WordData | null) {
  const saved = useRef(false);

  useEffect(() => {
    if (!data || saved.current || typeof indexedDB === "undefined") return;
    saved.current = true;
    putWord(data)
      .then(() => deleteOldWords(500))
      .catch(() => {});
  }, [data]);
}

/**
 * Try to retrieve a word from IndexedDB (offline fallback).
 */
export async function getOfflineWord(word: string): Promise<WordData | null> {
  if (typeof indexedDB === "undefined") return null;
  try {
    return await getWord(word);
  } catch {
    return null;
  }
}

/**
 * Bulk-cache an array of words (for pro offline packs).
 * Runs silently in the background.
 */
export async function bulkCacheWords(words: WordData[]): Promise<void> {
  if (typeof indexedDB === "undefined") return;
  for (const w of words) {
    await putWord(w).catch(() => {});
  }
  await deleteOldWords(5000).catch(() => {});
}
