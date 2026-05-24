import type { Metadata } from "next";
import Link from "next/link";
import { SITE_NAME, SITE_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: `About | ${SITE_NAME}`,
  description:
    "Learn about UrduMeaning — an AI-powered English to Urdu dictionary built to make the Urdu language accessible to everyone.",
  alternates: { canonical: `${SITE_URL}/about` },
};

export default function AboutPage() {
  return (
    <main className="mx-auto max-w-2xl px-4 py-12 md:py-16">
      <h1 className="text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100 mb-2">
        About UrduMeaning
      </h1>
      <p className="text-gray-500 dark:text-gray-400 mb-10 text-sm">
        Built by{" "}
        <a
          href="https://thetafoundry.com"
          target="_blank"
          rel="noopener noreferrer"
          className="text-indigo-600 dark:text-indigo-400 hover:underline"
        >
          ThetaFoundry LLC
        </a>
      </p>

      <div className="space-y-10 text-gray-700 dark:text-gray-300 leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            What is UrduMeaning?
          </h2>
          <p>
            UrduMeaning is a free English-to-Urdu dictionary that goes beyond
            simple word swaps. Every entry includes the Urdu meaning in
            Nastaliq script, Roman Urdu transliteration, real-world usage
            examples, synonyms, antonyms, etymology, memory hooks, and — where
            genuinely applicable — classical Urdu poetry and Islamic
            references.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            How it works
          </h2>
          <p>
            Each word is processed once by{" "}
            <a
              href="https://www.anthropic.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              Claude
            </a>{" "}
            (Anthropic&apos;s AI) and stored permanently in our database. The
            first time you look up a word that isn&apos;t in the dictionary
            yet, Claude generates a complete entry — typically within 15–30
            seconds. Every subsequent visit loads instantly from the cache.
            This means the dictionary grows with every search.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Why we built this
          </h2>
          <p>
            Urdu is spoken by over 230 million people worldwide, yet most
            digital dictionaries treat it as an afterthought — offering bare
            one-word translations without context, examples, or cultural
            nuance. We wanted a tool that respects the depth of the language
            and helps learners, writers, and native speakers alike.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            A note on accuracy
          </h2>
          <p>
            Word definitions are AI-generated and reviewed only at the
            structural level — not word by word. While Claude is highly
            capable and the results are generally excellent, occasional
            inaccuracies may occur. If you spot an error, use the flag button
            on any word page and we&apos;ll review it. We&apos;re continuously
            improving quality as the dictionary grows.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            Who we are
          </h2>
          <p>
            UrduMeaning is a product of{" "}
            <a
              href="https://thetafoundry.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              ThetaFoundry LLC
            </a>
            , a software company focused on building useful tools powered by
            modern AI.
          </p>
        </section>

        <div className="pt-4 border-t border-gray-200 dark:border-gray-800">
          <p className="text-sm text-gray-500 dark:text-gray-400">
            Questions or feedback?{" "}
            <Link
              href="/contact"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              Get in touch
            </Link>
            .
          </p>
        </div>
      </div>
    </main>
  );
}
