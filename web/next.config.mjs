import withPWAInit from "@ducanh2912/next-pwa";
import { setupDevPlatform } from "@cloudflare/next-on-pages/next-dev";

const disablePwa =
  process.env.NODE_ENV === "development" ||
  process.env.SKIP_PWA === "1";

const withPWA = withPWAInit({
  dest: "public",
  cacheOnFrontEndNav: true,
  aggressiveFrontEndNavCaching: true,
  reloadOnOnline: true,
  disable: disablePwa,
  workboxOptions: {
    disableDevLogs: true,
    runtimeCaching: [
      // API word definitions — cache-first, long TTL
      {
        urlPattern: /\/api\/word\/.+/,
        handler: "CacheFirst",
        options: {
          cacheName: "word-definitions",
          expiration: { maxEntries: 500, maxAgeSeconds: 60 * 60 * 24 * 365 },
          cacheableResponse: { statuses: [0, 200] },
        },
      },
      // Word of the Day — stale-while-revalidate, 1 day
      {
        urlPattern: /\/api\/word-of-the-day/,
        handler: "StaleWhileRevalidate",
        options: {
          cacheName: "wotd",
          expiration: { maxEntries: 2, maxAgeSeconds: 60 * 60 * 24 },
          cacheableResponse: { statuses: [0, 200] },
        },
      },
      // Search — network-first (needs fresh data)
      {
        urlPattern: /\/api\/search/,
        handler: "NetworkFirst",
        options: {
          cacheName: "search",
          expiration: { maxEntries: 50, maxAgeSeconds: 60 * 10 },
          cacheableResponse: { statuses: [0, 200] },
          networkTimeoutSeconds: 3,
        },
      },
      // Next.js static assets — cache-first
      {
        urlPattern: /\/_next\/static\/.*/,
        handler: "CacheFirst",
        options: {
          cacheName: "next-static",
          expiration: { maxEntries: 200, maxAgeSeconds: 60 * 60 * 24 * 365 },
        },
      },
      // Next.js image optimisation — stale-while-revalidate
      {
        urlPattern: /\/_next\/image.*/,
        handler: "StaleWhileRevalidate",
        options: {
          cacheName: "next-images",
          expiration: { maxEntries: 100, maxAgeSeconds: 60 * 60 * 24 * 30 },
        },
      },
      // Google Fonts — cache-first
      {
        urlPattern: /^https:\/\/fonts\.(googleapis|gstatic)\.com\/.*/,
        handler: "CacheFirst",
        options: {
          cacheName: "google-fonts",
          expiration: { maxEntries: 10, maxAgeSeconds: 60 * 60 * 24 * 365 },
          cacheableResponse: { statuses: [0, 200] },
        },
      },
    ],
  },
});

// Enable Cloudflare bindings in local dev
if (process.env.NODE_ENV === "development") {
  await setupDevPlatform();
}

/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    // Cloudflare handles image resizing; Next.js optimisation not supported on edge
    unoptimized: true,
    remotePatterns: [
      {
        protocol: "https",
        hostname: "*.blob.core.windows.net",
        pathname: "/**",
      },
    ],
  },
  headers: async () => [
    {
      source: "/sw.js",
      headers: [
        { key: "Cache-Control", value: "no-cache" },
        { key: "Service-Worker-Allowed", value: "/" },
      ],
    },
  ],
};

export default withPWA(nextConfig);
