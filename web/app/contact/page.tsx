import type { Metadata } from "next";
import Link from "next/link";
import { SITE_NAME, SITE_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: `Contact | ${SITE_NAME}`,
  description: "Get in touch with the UrduMeaning team — report errors, give feedback, or ask questions.",
  alternates: { canonical: `${SITE_URL}/contact` },
};

export default function ContactPage() {
  return (
    <main className="mx-auto max-w-2xl px-4 py-12 md:py-16">
      <h1 className="text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100 mb-2">
        Contact
      </h1>
      <p className="text-gray-500 dark:text-gray-400 mb-10">
        We&apos;d love to hear from you.
      </p>

      <div className="space-y-10 text-gray-700 dark:text-gray-300 leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Email us
          </h2>
          <p className="mb-4">
            For general questions, feedback, or partnership inquiries, email us
            at:
          </p>
          <a
            href="mailto:hello@urdumeaning.com"
            className="inline-flex items-center gap-2 rounded-xl border border-gray-200 dark:border-gray-700 bg-gray-50 dark:bg-gray-900 px-5 py-3 text-indigo-600 dark:text-indigo-400 font-medium hover:bg-gray-100 dark:hover:bg-gray-800 transition-colors"
          >
            <span>✉</span>
            hello@urdumeaning.com
          </a>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Reporting a definition error
          </h2>
          <p>
            Found a word with an inaccurate translation or example? The fastest
            way to flag it is via the{" "}
            <span className="font-medium text-gray-900 dark:text-gray-100">
              Flag
            </span>{" "}
            button on the word&apos;s page — it logs the issue directly and
            helps us prioritize corrections. For detailed feedback, email us
            with the word and what seems wrong.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Response time
          </h2>
          <p>
            We typically respond within 1–3 business days. We&apos;re a small
            team, so we appreciate your patience.
          </p>
        </section>

        <div className="pt-4 border-t border-gray-200 dark:border-gray-800 text-sm text-gray-500 dark:text-gray-400 space-y-1">
          <p>
            <Link
              href="/about"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              About UrduMeaning
            </Link>{" "}
            &nbsp;·&nbsp;{" "}
            <Link
              href="/privacy"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              Privacy Policy
            </Link>{" "}
            &nbsp;·&nbsp;{" "}
            <Link
              href="/terms"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              Terms of Service
            </Link>
          </p>
        </div>
      </div>
    </main>
  );
}
