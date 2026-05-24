import type { Metadata } from "next";
import type { CSSProperties } from "react";
import localFont from "next/font/local";
import AppShell from "@/components/AppShell";
import AuthProviderWrapper from "@/components/AuthProviderWrapper";
import InstallPrompt from "@/components/InstallPrompt";
import "./globals.css";

const geist = localFont({
  src: "./fonts/GeistVF.woff",
  variable: "--font-geist",
  weight: "100 900",
});

const htmlStyle = {
  "--font-nastaliq": '"Noto Nastaliq Urdu", "Noto Naskh Arabic", serif',
} as CSSProperties;

export const metadata: Metadata = {
  title: "UrduMeaning | English to Urdu Dictionary",
  description:
    "English to Urdu meanings, translations, examples, pronunciation, poetry, and more.",
  keywords: ["Urdu dictionary", "English to Urdu", "meaning in Urdu", "AI dictionary"],
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "UrduMeaning",
  },
  openGraph: {
    siteName: "UrduMeaning",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
  },
  robots: { index: true, follow: true },
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
        <AuthProviderWrapper>
          <AppShell>{children}</AppShell>
          <InstallPrompt />
        </AuthProviderWrapper>
      </body>
    </html>
  );
}
