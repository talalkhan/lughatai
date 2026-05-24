"use client";

import Script from "next/script";
import { GA_MEASUREMENT_ID, PLAUSIBLE_DOMAIN } from "@/lib/site";

export default function AnalyticsScripts() {
  const hasGa = GA_MEASUREMENT_ID.length > 0;
  const hasPlausible = PLAUSIBLE_DOMAIN.length > 0;

  if (!hasGa && !hasPlausible) {
    return null;
  }

  return (
    <>
      {hasGa && (
        <>
          <Script
            src={`https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`}
            strategy="afterInteractive"
          />
          <Script id="ga4-init" strategy="afterInteractive">
            {`
              window.dataLayer = window.dataLayer || [];
              function gtag(){dataLayer.push(arguments);}
              gtag('js', new Date());
              gtag('config', '${GA_MEASUREMENT_ID}', {
                anonymize_ip: true,
                transport_type: 'beacon'
              });
            `}
          </Script>
        </>
      )}

      {hasPlausible && (
        <Script
          data-domain={PLAUSIBLE_DOMAIN}
          src="https://plausible.io/js/script.js"
          strategy="afterInteractive"
        />
      )}
    </>
  );
}
