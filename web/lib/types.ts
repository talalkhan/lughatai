export interface Phonetic {
  ipa?: string;
  syllables?: string;
  stress?: string;
}

export interface Audio {
  en_url?: string | null;
  ur_url?: string | null;
}

export interface Learning {
  difficulty?: string;
  cefr_level?: string;
  frequency_rank?: number | null;
  contexts?: string[];
  sentiment?: string;
  emoji?: string;
}

export interface Etymology {
  origin_language?: string;
  origin_word?: string;
  origin_meaning?: string;
  history?: string;
  first_known_use?: string;
}

export interface ScriptVariants {
  nastaliq?: string;
  roman_urdu?: string;
  devanagari?: string | null;
}

export interface Translations {
  primary?: string;
  primary_roman?: string;
  alternatives?: string[];
  alternatives_roman?: string[];
  formal?: string | null;
  colloquial?: string | null;
}

export interface Synonyms {
  en?: string[];
  ur?: string[];
  ur_roman?: string[];
}

export interface Antonyms {
  en?: string[];
  ur?: string[];
  ur_roman?: string[];
}

export interface Example {
  en?: string;
  ur?: string;
  roman?: string;
}

export interface Confusable {
  word?: string;
  difference?: string;
}

export interface Meaning {
  pos?: string;
  register?: string | null;
  definition_en?: string;
  definition_ur?: string;
  translations?: Translations;
  synonyms?: Synonyms;
  antonyms?: Antonyms;
  collocations?: string[];
  examples?: Example[];
  confusables?: Confusable[];
}

export interface WordFamilyEntry {
  word?: string;
  pos?: string;
  ur?: string;
}

export interface RelatedWords {
  see_also?: string[];
  thematic_group?: string[];
}

export interface MemoryTip {
  mnemonic?: string;
  visual_association?: string;
}

export interface UrduPoetry {
  couplet_ur?: string;
  couplet_roman?: string;
  translation_en?: string;
  poet?: string;
  source?: string;
  ai_generated?: boolean;
}

export interface UrduProverb {
  proverb_ur?: string;
  proverb_roman?: string;
  translation_en?: string;
}

export interface IslamicReference {
  type?: string;
  reference?: string;
  text_ar?: string;
  text_ur?: string;
  translation_en?: string;
}

export interface MetaInfo {
  generated_by?: string;
  generated_at?: string;
  model?: string;
  version?: string;
  reviewed?: boolean;
}

export interface WordData {
  word: string;
  phonetic?: Phonetic;
  audio?: Audio;
  learning?: Learning;
  etymology?: Etymology;
  script_variants?: ScriptVariants;
  meanings?: Meaning[];
  word_family?: WordFamilyEntry[];
  related_words?: RelatedWords;
  memory_tip?: MemoryTip;
  urdu_poetry?: UrduPoetry | null;
  urdu_proverb?: UrduProverb | null;
  islamic_reference?: IslamicReference | null;
  _meta?: MetaInfo;
}

export interface SearchResult {
  word: string;
  urdu?: string;
  difficulty?: string;
}

export interface BrowseParams {
  context?: string;
  difficulty?: string;
  cefr?: string;
  page?: number;
  limit?: number;
}

export interface BrowseResult {
  words: WordSummary[];
  total: number;
  page: number;
  limit: number;
}

export interface WordSummary {
  word: string;
  urdu?: string;
  difficulty?: string;
  definitionEn?: string;
  emoji?: string;
}

export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string
  ) {
    super(message);
    this.name = "ApiError";
  }
}

// ── Auth ───────────────────────────────────────────────────────────────────

export interface UserDto {
  id: number;
  username: string;
  email: string;
  tier: "free" | "pro";
}

export interface AuthResult {
  accessToken: string;
  refreshToken: string;
  user: UserDto;
}

// ── Favorites / History ────────────────────────────────────────────────────

export interface FavoriteEntry {
  word: string;
  urdu?: string;
  difficulty?: string;
  definition_en?: string;
  emoji?: string;
  created_at: string;
}

export interface HistoryEntry {
  word: string;
  urdu?: string;
  difficulty?: string;
  emoji?: string;
  looked_up_at: string;
}

// ── Roman Urdu Search ──────────────────────────────────────────────────────

export interface RomanSearchResult {
  results: SearchResult[];
  source: "db" | "ai" | "none";
  interpreted_as?: string;
}

// ── Flashcards (SM-2) ──────────────────────────────────────────────────────

export interface FlashcardState {
  word: string;
  easeFactor: number;   // starts at 2.5
  interval: number;     // days until next review
  repetitions: number;  // number of successful reviews
  nextReview: string;   // ISO date
  lastQuality: number;  // 0-5
}

// ── Quiz ───────────────────────────────────────────────────────────────────

export interface QuizQuestion {
  word: string;
  urdu: string;
  correct: string;        // correct answer text
  choices: string[];      // 4 shuffled choices
  mode: "en_to_ur" | "ur_to_en";
}
