import type { Metadata } from "next";
import localFont from "next/font/local";
import { Noto_Nastaliq_Urdu } from "next/font/google";
import AuthProviderWrapper from "@/components/AuthProviderWrapper";
import InstallPrompt from "@/components/InstallPrompt";
import "./globals.css";

const geist = localFont({
  src: "./fonts/GeistVF.woff",
  variable: "--font-geist",
  weight: "100 900",
});

const nastaliq = Noto_Nastaliq_Urdu({
  weight: ["400", "700"],
  subsets: ["arabic"],
  variable: "--font-nastaliq",
});

export const metadata: Metadata = {
  title: "LughatAI — AI-Powered English to Urdu Dictionary",
  description:
    "The richest English-to-Urdu dictionary, powered by AI. Find detailed translations, examples, poetry, and more.",
  keywords: ["Urdu dictionary", "English to Urdu", "translation", "AI dictionary"],
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "LughatAI",
  },
  openGraph: {
    siteName: "LughatAI",
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
    <html lang="en" className={`${geist.variable} ${nastaliq.variable}`}>
      <body className="antialiased bg-white dark:bg-gray-950 text-gray-900 dark:text-gray-100 min-h-screen">
        <AuthProviderWrapper>
          {children}
          <InstallPrompt />
        </AuthProviderWrapper>
      </body>
    </html>
  );
}
