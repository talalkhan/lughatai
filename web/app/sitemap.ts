export const runtime = "edge";

import { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/site";

const API_URL = process.env.NEXT_PUBLIC_API_URL;
const SITEMAP_FETCH_TIMEOUT_MS = 10_000;
const PAGE_LIMIT = 50; // matches BrowseController max

export const dynamic = "force-dynamic";
export const revalidate = 3600;

interface WordRow {
  word: string;
  updated_at?: string;
}

interface BrowseResponse {
  words: WordRow[];
}

async function fetchAllWords(): Promise<WordRow[]> {
  if (!API_URL) {
    console.warn("[sitemap] NEXT_PUBLIC_API_URL is not set — word URLs will be omitted from sitemap");
    return [];
  }

  try {
    const words: WordRow[] = [];
    let page = 1;
    const maxPages = 200; // safety cap: 200 * 50 = 10 000 words

    while (page <= maxPages) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), SITEMAP_FETCH_TIMEOUT_MS);

      let res: Response;
      try {
        res = await fetch(
          `${API_URL}/api/browse?page=${page}&limit=${PAGE_LIMIT}`,
          { cache: "no-store", signal: controller.signal }
        );
      } catch {
        clearTimeout(timeout);
        break;
      }
      clearTimeout(timeout);

      if (!res.ok) break;
      const data = (await res.json()) as BrowseResponse;
      words.push(...data.words.map(({ word }) => ({ word })));
      if (data.words.length < PAGE_LIMIT) break;
      page++;
    }

    return words;
  } catch {
    return [];
  }
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const words = await fetchAllWords();

  const wordUrls: MetadataRoute.Sitemap = words.map(({ word }) => ({
    url: `${SITE_URL}/word/${encodeURIComponent(word)}`,
    changeFrequency: "monthly",
    priority: 0.8,
  }));

  const staticPages: MetadataRoute.Sitemap = [
    { url: SITE_URL, changeFrequency: "daily", priority: 1.0 },
    { url: `${SITE_URL}/browse`, changeFrequency: "daily", priority: 0.9 },
    { url: `${SITE_URL}/flashcards`, changeFrequency: "monthly", priority: 0.6 },
    { url: `${SITE_URL}/quiz`, changeFrequency: "monthly", priority: 0.6 },
  ];

  return [...staticPages, ...wordUrls];
}
