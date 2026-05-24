import type { Metadata } from "next";
import Link from "next/link";
import { SITE_NAME, SITE_URL } from "@/lib/site";

export const metadata: Metadata = {
  title: `Privacy Policy | ${SITE_NAME}`,
  description: "UrduMeaning privacy policy — what data we collect, how we use it, and your rights.",
  alternates: { canonical: `${SITE_URL}/privacy` },
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-2xl px-4 py-12 md:py-16">
      <h1 className="text-3xl font-bold tracking-tight text-gray-900 dark:text-gray-100 mb-2">
        Privacy Policy
      </h1>
      <p className="text-sm text-gray-500 dark:text-gray-400 mb-10">
        Effective date: 24 May 2026 &nbsp;·&nbsp; ThetaFoundry LLC
      </p>

      <div className="space-y-10 text-gray-700 dark:text-gray-300 leading-relaxed">
        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            1. Overview
          </h2>
          <p>
            UrduMeaning (&ldquo;we&rdquo;, &ldquo;our&rdquo;, or
            &ldquo;us&rdquo;) is operated by ThetaFoundry LLC. We respect your
            privacy. This policy explains what information we collect when you
            use urdumeaning.com, how we use it, and what choices you have.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            2. Information we collect
          </h2>
          <div className="space-y-4">
            <div>
              <h3 className="font-medium text-gray-800 dark:text-gray-200 mb-1">
                Server and access logs
              </h3>
              <p>
                Our hosting provider (Microsoft Azure) automatically records
                standard server access logs, including your IP address, browser
                user agent, the pages you visit, and timestamps. These logs are
                used to monitor uptime and diagnose errors. They are retained
                for 30 days and are not used for advertising.
              </p>
            </div>
            <div>
              <h3 className="font-medium text-gray-800 dark:text-gray-200 mb-1">
                Cloudflare
              </h3>
              <p>
                Our traffic is routed through Cloudflare for DNS resolution and
                DDoS protection. Cloudflare may collect IP addresses and request
                metadata as part of this service. See{" "}
                <a
                  href="https://www.cloudflare.com/privacypolicy/"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-indigo-600 dark:text-indigo-400 hover:underline"
                >
                  Cloudflare&apos;s Privacy Policy
                </a>{" "}
                for details.
              </p>
            </div>
            <div>
              <h3 className="font-medium text-gray-800 dark:text-gray-200 mb-1">
                Words you search
              </h3>
              <p>
                When you look up a word, it is sent to our API to retrieve or
                generate a definition. We store the word and its definition
                permanently in our database so future visitors benefit from the
                cached result. Search queries are not linked to your identity.
              </p>
            </div>
            <div>
              <h3 className="font-medium text-gray-800 dark:text-gray-200 mb-1">
                Cookies
              </h3>
              <p>
                We do not set any tracking or advertising cookies. We may use
                small functional cookies (e.g. for session management once
                accounts are introduced in a future update).
              </p>
            </div>
          </div>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            3. How we use your information
          </h2>
          <ul className="list-disc list-inside space-y-2 ml-1">
            <li>To deliver and improve the dictionary service</li>
            <li>To monitor uptime, diagnose errors, and prevent abuse</li>
            <li>To generate AI-powered definitions via Anthropic&apos;s Claude API</li>
          </ul>
          <p className="mt-4">
            We do not sell, rent, or share your personal information with third
            parties for marketing purposes.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            4. Third-party services
          </h2>
          <p className="mb-3">
            We use the following third-party services to operate the site:
          </p>
          <div className="overflow-x-auto">
            <table className="w-full text-sm border-collapse">
              <thead>
                <tr className="border-b border-gray-200 dark:border-gray-700">
                  <th className="text-left py-2 pr-4 font-medium text-gray-900 dark:text-gray-100">
                    Service
                  </th>
                  <th className="text-left py-2 pr-4 font-medium text-gray-900 dark:text-gray-100">
                    Purpose
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100 dark:divide-gray-800">
                <tr>
                  <td className="py-2 pr-4">Microsoft Azure</td>
                  <td className="py-2">Hosting (API, frontend, database)</td>
                </tr>
                <tr>
                  <td className="py-2 pr-4">Cloudflare</td>
                  <td className="py-2">DNS, CDN, DDoS protection</td>
                </tr>
                <tr>
                  <td className="py-2 pr-4">Anthropic</td>
                  <td className="py-2">AI-generated word definitions</td>
                </tr>
                <tr>
                  <td className="py-2 pr-4">Azure Cognitive Speech</td>
                  <td className="py-2">Text-to-speech pronunciation audio</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            5. Data retention
          </h2>
          <p>
            Server access logs are retained for up to 30 days. Word definitions
            stored in our database are retained indefinitely as they form the
            core product. If you contact us by email, we retain that
            correspondence for as long as necessary to respond.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            6. Your rights
          </h2>
          <p>
            Depending on where you are located, you may have the right to
            access, correct, or delete personal information we hold about you.
            Because we do not collect personally identifiable information beyond
            standard server logs, most requests will relate to log data that is
            automatically purged within 30 days. To make a request, contact us
            at the address below.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            7. Children&apos;s privacy
          </h2>
          <p>
            UrduMeaning is not directed at children under 13. We do not
            knowingly collect personal information from children.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            8. Changes to this policy
          </h2>
          <p>
            We may update this policy as the service evolves (for example, when
            user accounts are introduced). The effective date at the top of this
            page will reflect any changes.
          </p>
        </section>

        <section>
          <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100 mb-3">
            9. Contact
          </h2>
          <p>
            Questions about this policy?{" "}
            <Link
              href="/contact"
              className="text-indigo-600 dark:text-indigo-400 hover:underline"
            >
              Contact us
            </Link>{" "}
            and we&apos;ll respond promptly.
          </p>
        </section>
      </div>
    </main>
  );
}
