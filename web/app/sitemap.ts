import { MetadataRoute } from "next";

const BASE_URL = process.env.NEXT_PUBLIC_SITE_URL ?? "https://lughatai.com";
const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:5000";

export const dynamic = "force-dynamic";
export const revalidate = 3600; // regenerate every hour

interface WordRow {
  word: string;
  updated_at?: string;
}

async function fetchAllWords(): Promise<WordRow[]> {
  try {
    // Paginate to collect all words; each page returns up to 1000
    const words: WordRow[] = [];
    let page = 1;
    const limit = 1000;

    while (true) {
      const res = await fetch(
        `${API_URL}/api/browse?page=${page}&limit=${limit}`,
        { cache: "no-store" }
      );
      if (!res.ok) break;
      const data = await res.json();
      words.push(...data.words.map((w: any) => ({ word: w.word })));
      if (data.words.length < limit) break;
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
    url: `${BASE_URL}/word/${encodeURIComponent(word)}`,
    changeFrequency: "monthly",
    priority: 0.8,
  }));

  const staticPages: MetadataRoute.Sitemap = [
    { url: BASE_URL, changeFrequency: "daily", priority: 1.0 },
    { url: `${BASE_URL}/browse`, changeFrequency: "daily", priority: 0.9 },
    { url: `${BASE_URL}/flashcards`, changeFrequency: "monthly", priority: 0.6 },
    { url: `${BASE_URL}/quiz`, changeFrequency: "monthly", priority: 0.6 },
  ];

  return [...staticPages, ...wordUrls];
}
