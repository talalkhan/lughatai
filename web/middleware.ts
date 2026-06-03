import { NextRequest, NextResponse } from "next/server";

const ALLOWED_SEARCH_CRAWLER_PATTERN =
  /googlebot|bingbot|duckduckbot|slurp|yandexbot|baiduspider|applebot/i;

const NOISY_CRAWLER_PATTERN =
  /semrush|ahrefs|mj12bot|dotbot|bytespider|gptbot|ccbot|claudebot|perplexity|amazonbot|petalbot/i;

const WORD_PATH_PATTERN = /^\/word\/[a-zA-Z]+\/?$/;

function blockedCrawlerResponse() {
  return new NextResponse("Word pages are unavailable to this crawler.", {
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
  const pathname = request.nextUrl.pathname;

  if (!WORD_PATH_PATTERN.test(pathname)) {
    return new NextResponse("Word not found", {
      status: 404,
      headers: {
        "X-Robots-Tag": "noindex, nofollow",
      },
    });
  }

  if (NOISY_CRAWLER_PATTERN.test(userAgent)) {
    return blockedCrawlerResponse();
  }

  if (ALLOWED_SEARCH_CRAWLER_PATTERN.test(userAgent)) {
    return NextResponse.next();
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
