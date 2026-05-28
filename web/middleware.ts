import { NextRequest, NextResponse } from "next/server";

const BOT_USER_AGENT_PATTERN =
  /bot|crawler|spider|crawling|facebookexternalhit|slurp|bingpreview|duckduckgo|baiduspider|yandex|semrush|ahrefs|mj12bot|dotbot|petalbot|bytespider|gptbot|ccbot|claudebot|perplexity|amazonbot/i;

function blockedCrawlerResponse() {
  return new NextResponse("Word pages are temporarily unavailable to crawlers.", {
    status: 429,
    headers: {
      "Cache-Control": "public, max-age=300",
      "Retry-After": "3600",
      "X-Robots-Tag": "noindex, nofollow",
    },
  });
}

export function middleware(request: NextRequest) {
  const userAgent = request.headers.get("user-agent") ?? "";
  const accept = request.headers.get("accept") ?? "";
  const secFetchDest = request.headers.get("sec-fetch-dest") ?? "";
  const secFetchMode = request.headers.get("sec-fetch-mode") ?? "";

  if (BOT_USER_AGENT_PATTERN.test(userAgent)) {
    return blockedCrawlerResponse();
  }

  const isBrowserDocumentNavigation =
    accept.includes("text/html") &&
    secFetchDest === "document" &&
    secFetchMode === "navigate";

  return isBrowserDocumentNavigation ? NextResponse.next() : blockedCrawlerResponse();
}

export const config = {
  matcher: "/word/:path*",
};
