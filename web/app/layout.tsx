import type { Metadata } from "next";
import type { CSSProperties } from "react";
import localFont from "next/font/local";
import AnalyticsScripts from "@/components/AnalyticsScripts";
import AppShell from "@/components/AppShell";
import AuthProviderWrapper from "@/components/AuthProviderWrapper";
import InstallPrompt from "@/components/InstallPrompt";
import {
  DEFAULT_KEYWORDS,
  DEFAULT_OG_IMAGE,
  SITE_DESCRIPTION,
  SITE_NAME,
  SITE_TITLE,
  SITE_URL,
} from "@/lib/site";
import "./globals.css";

const geist = localFont({
  src: "./fonts/GeistVF.woff",
  variable: "--font-geist",
  weight: "100 900",
});

const htmlStyle = {
  "--font-nastaliq": '"Noto Nastaliq Urdu", "Noto Naskh Arabic", serif',
} as CSSProperties;

const googleSiteVerification = process.env.GOOGLE_SITE_VERIFICATION?.trim();
const bingSiteVerification = process.env.BING_SITE_VERIFICATION?.trim();
const verification: Metadata["verification"] = {};

if (googleSiteVerification) {
  verification.google = googleSiteVerification;
}

if (bingSiteVerification) {
  verification.other = {
    "msvalidate.01": bingSiteVerification,
  };
}

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  applicationName: SITE_NAME,
  title: SITE_TITLE,
  description: SITE_DESCRIPTION,
  keywords: DEFAULT_KEYWORDS,
  alternates: {
    canonical: "/",
  },
  manifest: "/manifest.json",
  icons: {
    icon: [
      { url: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
      { url: "/icons/icon-512.png", sizes: "512x512", type: "image/png" },
    ],
    apple: [{ url: "/icons/icon-180.png", sizes: "180x180", type: "image/png" }],
    shortcut: ["/icons/icon-192.png"],
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: SITE_NAME,
  },
  openGraph: {
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    url: SITE_URL,
    siteName: SITE_NAME,
    type: "website",
    images: [
      {
        url: DEFAULT_OG_IMAGE,
        alt: `${SITE_NAME} icon`,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    images: [DEFAULT_OG_IMAGE],
  },
  robots: { index: true, follow: true },
  verification,
  other: {
    "mobile-web-app-capable": "yes",
  },
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en"
      className={geist.variable}
      style={htmlStyle}
    >
      <body className="antialiased bg-white dark:bg-gray-950 text-gray-900 dark:text-gray-100 min-h-screen">
        <AnalyticsScripts />
        <AuthProviderWrapper>
          <AppShell>{children}</AppShell>
          <InstallPrompt />
        </AuthProviderWrapper>
      </body>
    </html>
  );
}
