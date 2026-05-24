export const SITE_NAME = "UrduMeaning";
export const SITE_TITLE = "UrduMeaning | English to Urdu Dictionary";
export const SITE_DESCRIPTION =
  "English to Urdu meanings, translations, examples, pronunciation, poetry, and more.";

const rawSiteUrl = process.env.NEXT_PUBLIC_SITE_URL?.trim() || "https://urdumeaning.com";

export const SITE_URL = rawSiteUrl.replace(/\/+$/, "");
export const DEFAULT_OG_IMAGE = "/icons/icon-512.png";
export const DEFAULT_KEYWORDS = [
  "Urdu dictionary",
  "English to Urdu",
  "meaning in Urdu",
  "English to Urdu dictionary",
  "Urdu meanings",
  "AI dictionary",
];

export const GA_MEASUREMENT_ID = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID?.trim() || "";
export const PLAUSIBLE_DOMAIN = process.env.NEXT_PUBLIC_PLAUSIBLE_DOMAIN?.trim() || "";
