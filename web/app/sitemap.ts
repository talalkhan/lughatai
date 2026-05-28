import { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/site";

export const dynamic = "force-dynamic";
export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticPages: MetadataRoute.Sitemap = [
    { url: SITE_URL, changeFrequency: "daily", priority: 1.0 },
    { url: `${SITE_URL}/browse`, changeFrequency: "daily", priority: 0.9 },
    { url: `${SITE_URL}/flashcards`, changeFrequency: "monthly", priority: 0.6 },
    { url: `${SITE_URL}/quiz`, changeFrequency: "monthly", priority: 0.6 },
  ];

  return staticPages;
}
