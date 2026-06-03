import { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/site";

export const dynamic = "force-dynamic";
export const revalidate = 3600;

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:5000";
const SITEMAP_WORD_LIMIT = Number(process.env.SITEMAP_WORD_LIMIT ?? "1000");
const PAGE_SIZE = 50;

interface BrowseWord {
  word?: string;
}

interface BrowseResponse {
  words?: BrowseWord[];
}

async function getSitemapWords(): Promise<string[]> {
  const maxWords = Number.isFinite(SITEMAP_WORD_LIMIT)
    ? Math.max(0, Math.min(SITEMAP_WORD_LIMIT, 10_000))
    : 1000;

  if (maxWords === 0) return [];

  const pages = Math.ceil(maxWords / PAGE_SIZE);
  const words: string[] = [];

  for (let page = 1; page <= pages; page += 1) {
    const limit = Math.min(PAGE_SIZE, maxWords - words.length);
    const url = `${API_URL}/api/browse?page=${page}&limit=${limit}`;

    const response = await fetch(url, {
      next: { revalidate },
    });

    if (!response.ok) break;

    const data = (await response.json()) as BrowseResponse;
    const pageWords = data.words
      ?.map((entry) => entry.word?.trim().toLowerCase())
      .filter((word): word is string => Boolean(word && /^[a-z]+$/.test(word))) ?? [];

    if (pageWords.length === 0) break;

    words.push(...pageWords);
  }

  return Array.from(new Set(words)).slice(0, maxWords);
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticPages: MetadataRoute.Sitemap = [
    { url: SITE_URL, changeFrequency: "daily", priority: 1.0 },
    { url: `${SITE_URL}/browse`, changeFrequency: "daily", priority: 0.9 },
    { url: `${SITE_URL}/flashcards`, changeFrequency: "monthly", priority: 0.6 },
    { url: `${SITE_URL}/quiz`, changeFrequency: "monthly", priority: 0.6 },
  ];

  try {
    const wordPages: MetadataRoute.Sitemap = (await getSitemapWords()).map((word) => ({
      url: `${SITE_URL}/word/${encodeURIComponent(word)}`,
      changeFrequency: "monthly",
      priority: 0.7,
    }));

    return [...staticPages, ...wordPages];
  } catch {
    return staticPages;
  }
}
