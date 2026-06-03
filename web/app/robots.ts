import { MetadataRoute } from "next";
import { SITE_URL } from "@/lib/site";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: [
      {
        userAgent: "*",
        allow: "/",
        disallow: ["/api/"],
      },
      {
        userAgent: [
          "AhrefsBot",
          "SemrushBot",
          "MJ12bot",
          "DotBot",
          "GPTBot",
          "CCBot",
          "ClaudeBot",
          "Bytespider",
          "PetalBot",
          "Amazonbot",
        ],
        disallow: ["/word/"],
      },
    ],
    sitemap: `${SITE_URL}/sitemap.xml`,
  };
}
