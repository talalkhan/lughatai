import { NextRequest, NextResponse } from "next/server";

const BOT_USER_AGENT_PATTERN =
  /bot|crawler|spider|crawling|facebookexternalhit|slurp|bingpreview|duckduckgo|baiduspider|yandex|semrush|ahrefs|mj12bot|dotbot|petalbot|bytespider|gptbot|ccbot|claudebot|perplexity|amazonbot/i;

export function middleware(request: NextRequest) {
  const userAgent = request.headers.get("user-agent") ?? "";

  if (BOT_USER_AGENT_PATTERN.test(userAgent)) {
    return new NextResponse("Word pages are temporarily unavailable to crawlers.", {
      status: 429,
      headers: {
        "Cache-Control": "public, max-age=300",
        "Retry-After": "3600",
        "X-Robots-Tag": "noindex, nofollow",
      },
    });
  }

  return NextResponse.next();
}

export const config = {
  matcher: "/word/:path*",
};
