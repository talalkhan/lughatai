import type { Metadata } from "next";
import { notFound } from "next/navigation";
import Link from "next/link";
import AudioPlayer from "@/components/AudioPlayer";
import FavoriteToggle from "@/components/FavoriteToggle";
import FlagButton from "@/components/FlagButton";
import WordCacheWriter from "@/components/WordCacheWriter";
import { getWord } from "@/lib/api";
import { Meaning, WordData } from "@/lib/types";
import { ApiError } from "@/lib/types";

interface Props {
  params: { slug: string };
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  try {
    const word = await getWord(params.slug);
    const primary = word.meanings?.[0];
    const urdu = word.script_variants?.nastaliq;
    const description = primary?.definition_en
      ? primary.definition_en.slice(0, 160)
      : `${params.slug} meaning in Urdu`;

    return {
      title: `${word.word} in Urdu | LughatAI`,
      description,
      openGraph: {
        title: `${word.word} — ${urdu ?? "Urdu Translation"}`,
        description,
        type: "article",
      },
    };
  } catch {
    return { title: "Word Not Found | LughatAI" };
  }
}

function DiffBadge({ label, color }: { label: string; color: string }) {
  return (
    <span className={`text-xs px-2.5 py-1 rounded-full font-medium ${color}`}>
      {label}
    </span>
  );
}

const DIFFICULTY_COLORS: Record<string, string> = {
  beginner: "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200",
  intermediate: "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200",
  advanced: "bg-orange-100 text-orange-800 dark:bg-orange-900 dark:text-orange-200",
  expert: "bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200",
};

function PillTag({ children, href }: { children: React.ReactNode; href?: string }) {
  const cls = "inline-flex items-center px-3 py-1 rounded-full text-sm bg-indigo-50 dark:bg-indigo-950 text-indigo-700 dark:text-indigo-300 hover:bg-indigo-100 dark:hover:bg-indigo-900 transition-colors";
  if (href) return <Link href={href} className={cls}>{children}</Link>;
  return <span className={cls}>{children}</span>;
}

function MeaningSection({ meaning }: { meaning: Meaning; index: number }) {
  return (
    <div className="p-6 bg-white dark:bg-gray-900 rounded-2xl border border-gray-200 dark:border-gray-700 space-y-5">
      <div className="flex items-center gap-3 flex-wrap">
        {meaning.pos && (
          <span className="px-3 py-1 bg-indigo-600 text-white text-sm font-medium rounded-full">
            {meaning.pos}
          </span>
        )}
        {meaning.register && (
          <span className="px-3 py-1 bg-gray-100 dark:bg-gray-800 text-gray-600 dark:text-gray-400 text-sm rounded-full">
            {meaning.register}
          </span>
        )}
      </div>

      {meaning.definition_en && (
        <p className="text-gray-800 dark:text-gray-200 text-base">{meaning.definition_en}</p>
      )}

      {meaning.definition_ur && (
        <p dir="rtl" lang="ur" className="font-nastaliq text-xl text-gray-700 dark:text-gray-300">
          {meaning.definition_ur}
        </p>
      )}

      {meaning.translations?.primary && (
        <div className="space-y-1">
          <p dir="rtl" lang="ur" className="font-nastaliq text-2xl text-indigo-700 dark:text-indigo-300">
            {meaning.translations.primary}
          </p>
          {meaning.translations.primary_roman && (
            <p className="text-sm text-gray-500 dark:text-gray-400 italic">
              {meaning.translations.primary_roman}
            </p>
          )}
          {(meaning.translations.formal || meaning.translations.colloquial) && (
            <div className="flex gap-4 mt-2 text-sm">
              {meaning.translations.formal && (
                <span className="text-gray-600 dark:text-gray-400">
                  <span className="font-medium">Formal:</span>{" "}
                  <span dir="rtl" lang="ur" className="font-nastaliq">{meaning.translations.formal}</span>
                </span>
              )}
              {meaning.translations.colloquial && (
                <span className="text-gray-600 dark:text-gray-400">
                  <span className="font-medium">Colloquial:</span>{" "}
                  <span dir="rtl" lang="ur" className="font-nastaliq">{meaning.translations.colloquial}</span>
                </span>
              )}
            </div>
          )}
        </div>
      )}

      {meaning.synonyms && (meaning.synonyms.en?.length ?? 0) > 0 && (
        <div>
          <h4 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
            Synonyms
          </h4>
          <div className="flex flex-wrap gap-2">
            {meaning.synonyms.en?.map((syn) => (
              <PillTag key={syn} href={`/word/${encodeURIComponent(syn.toLowerCase())}`}>
                {syn}
              </PillTag>
            ))}
            {meaning.synonyms.ur?.map((syn, i) => (
              <span key={i} dir="rtl" lang="ur" className="inline-flex items-center px-3 py-1 rounded-full text-sm bg-gray-50 dark:bg-gray-800 font-nastaliq text-gray-700 dark:text-gray-300">
                {syn}
              </span>
            ))}
          </div>
        </div>
      )}

      {meaning.antonyms && (meaning.antonyms.en?.length ?? 0) > 0 && (
        <div>
          <h4 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
            Antonyms
          </h4>
          <div className="flex flex-wrap gap-2">
            {meaning.antonyms.en?.map((ant) => (
              <PillTag key={ant} href={`/word/${encodeURIComponent(ant.toLowerCase())}`}>
                {ant}
              </PillTag>
            ))}
            {meaning.antonyms.ur?.map((ant, i) => (
              <span key={i} dir="rtl" lang="ur" className="inline-flex items-center px-3 py-1 rounded-full text-sm bg-gray-50 dark:bg-gray-800 font-nastaliq text-gray-700 dark:text-gray-300">
                {ant}
              </span>
            ))}
          </div>
        </div>
      )}

      {(meaning.collocations?.length ?? 0) > 0 && (
        <div>
          <h4 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
            Common Collocations
          </h4>
          <ul className="list-disc list-inside text-sm text-gray-600 dark:text-gray-400 space-y-0.5">
            {meaning.collocations!.map((c, i) => <li key={i}>{c}</li>)}
          </ul>
        </div>
      )}

      {(meaning.examples?.length ?? 0) > 0 && (
        <div>
          <h4 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-3">
            Example Sentences
          </h4>
          <div className="space-y-4">
            {meaning.examples!.map((ex, i) => (
              <div key={i} className="bg-gray-50 dark:bg-gray-800 rounded-xl p-4 space-y-1">
                {ex.en && <p className="text-gray-800 dark:text-gray-200 text-sm">{ex.en}</p>}
                {ex.ur && (
                  <p dir="rtl" lang="ur" className="font-nastaliq text-lg text-gray-700 dark:text-gray-300">
                    {ex.ur}
                  </p>
                )}
                {ex.roman && (
                  <p className="text-xs text-gray-500 dark:text-gray-500 italic">{ex.roman}</p>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {(meaning.confusables?.length ?? 0) > 0 && (
        <div>
          <h4 className="text-sm font-semibold text-gray-500 dark:text-gray-400 uppercase tracking-wide mb-2">
            Easily Confused With
          </h4>
          <div className="space-y-2">
            {meaning.confusables!.map((c, i) => (
              <div key={i} className="flex gap-2 text-sm">
                <span className="font-medium text-gray-800 dark:text-gray-200">{c.word}:</span>
                <span className="text-gray-600 dark:text-gray-400">{c.difference}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

export default async function WordDetailPage({ params }: Props) {
  let word: WordData;
  try {
    word = await getWord(params.slug);
  } catch (err) {
    if (err instanceof ApiError && err.status === 404) notFound();
    throw err;
  }

  const urdu = word.script_variants?.nastaliq;
  const romanUrdu = word.script_variants?.roman_urdu;
  const difficulty = word.learning?.difficulty;
  const leadMeaning = word.meanings?.[0];

  const jsonLd = {
    "@context": "https://schema.org",
    "@type": "DefinedTerm",
    name: word.word,
    description: word.meanings?.[0]?.definition_en,
    inDefinedTermSet: "https://lughatai.com",
  };

  return (
    <>
      <WordCacheWriter word={word} />
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd) }}
      />

      <main className="mx-auto max-w-5xl px-4 py-6 sm:py-8">
        <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-2">
            <Link
              href="/"
              className="inline-flex min-h-[44px] items-center rounded-full border border-gray-200 bg-white px-4 text-sm font-medium text-gray-700 transition-colors hover:bg-gray-100 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-200 dark:hover:bg-gray-800"
            >
              ← Search
            </Link>
            <Link
              href="/browse"
              className="inline-flex min-h-[44px] items-center rounded-full border border-gray-200 bg-white px-4 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-100 hover:text-gray-900 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-300 dark:hover:bg-gray-800 dark:hover:text-white"
            >
              Browse
            </Link>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <FavoriteToggle word={word.word} />
            <FlagButton word={word.word} variant="pill" />
          </div>
        </div>

        <header className="mb-8 grid gap-4 lg:grid-cols-[minmax(0,1fr)_280px]">
          <section className="rounded-[2rem] border border-gray-200 bg-white p-6 shadow-sm dark:border-gray-700 dark:bg-gray-900 sm:p-7">
            <div className="flex flex-wrap items-start gap-4">
              {word.learning?.emoji && (
                <span className="flex h-16 w-16 items-center justify-center rounded-3xl bg-indigo-50 text-4xl dark:bg-indigo-950/60">
                  {word.learning.emoji}
                </span>
              )}
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <h1 className="text-4xl font-bold capitalize tracking-tight text-gray-950 dark:text-white">
                    {word.word}
                  </h1>
                  {difficulty && (
                    <DiffBadge
                      label={difficulty}
                      color={DIFFICULTY_COLORS[difficulty] ?? "bg-gray-100 text-gray-700"}
                    />
                  )}
                  {word.learning?.cefr_level && (
                    <DiffBadge
                      label={word.learning.cefr_level}
                      color="bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200"
                    />
                  )}
                </div>

                {word.phonetic?.ipa && (
                  <p className="mt-2 text-sm text-gray-500 dark:text-gray-400">
                    {word.phonetic.ipa}
                    {word.phonetic.syllables && ` · ${word.phonetic.syllables}`}
                  </p>
                )}

                {leadMeaning?.definition_en && (
                  <p className="mt-4 max-w-2xl text-base text-gray-700 dark:text-gray-300">
                    {leadMeaning.definition_en}
                  </p>
                )}

                <div className="mt-5 flex flex-wrap gap-2">
                  <AudioPlayer url={word.audio?.en_url} lang="EN" />
                  <AudioPlayer url={word.audio?.ur_url} lang="UR" />
                </div>

                {word.learning?.contexts && word.learning.contexts.length > 0 && (
                  <div className="mt-5 flex flex-wrap gap-2">
                    {word.learning.contexts.map((ctx) => (
                      <Link
                        key={ctx}
                        href={`/browse?context=${ctx}`}
                        className="rounded-full bg-gray-100 px-3 py-1 text-xs font-medium text-gray-600 transition-colors hover:bg-indigo-50 hover:text-indigo-700 dark:bg-gray-800 dark:text-gray-300 dark:hover:bg-indigo-950 dark:hover:text-indigo-300"
                      >
                        {ctx}
                      </Link>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </section>

          <aside className="rounded-[2rem] border border-indigo-100 bg-gradient-to-br from-indigo-50 via-white to-sky-50 p-6 shadow-sm dark:border-indigo-900/50 dark:from-indigo-950/50 dark:via-gray-900 dark:to-slate-950 sm:p-7">
            <p className="text-xs font-semibold uppercase tracking-[0.25em] text-indigo-600 dark:text-indigo-300">
              Urdu rendering
            </p>
            {urdu && (
              <p dir="rtl" lang="ur" className="mt-6 font-nastaliq text-5xl text-indigo-700 dark:text-indigo-300 lg:text-right">
                {urdu}
              </p>
            )}
            {romanUrdu && (
              <p className="mt-4 text-lg italic text-gray-500 dark:text-gray-400 lg:text-right">
                {romanUrdu}
              </p>
            )}
            {leadMeaning?.translations?.primary_roman && leadMeaning.translations.primary_roman !== romanUrdu && (
              <p className="mt-2 text-sm text-gray-500 dark:text-gray-400 lg:text-right">
                Primary translation: {leadMeaning.translations.primary_roman}
              </p>
            )}
          </aside>
        </header>

        {/* Meanings */}
        {(word.meanings?.length ?? 0) > 0 && (
          <section className="mb-8 space-y-4">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-gray-100">Meanings</h2>
            {word.meanings!.map((m, i) => (
              <MeaningSection key={i} meaning={m} index={i} />
            ))}
          </section>
        )}

        <div className="grid sm:grid-cols-2 gap-6 mb-8">
          {/* Word Family */}
          {(word.word_family?.length ?? 0) > 0 && (
            <section className="p-5 bg-white dark:bg-gray-900 rounded-2xl border border-gray-200 dark:border-gray-700">
              <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 mb-3">Word Family</h2>
              <div className="space-y-2">
                {word.word_family!.map((wf, i) => (
                  <div key={i} className="flex items-center justify-between">
                    <Link
                      href={`/word/${encodeURIComponent((wf.word ?? "").toLowerCase())}`}
                      className="font-medium text-indigo-600 dark:text-indigo-400 hover:underline"
                    >
                      {wf.word}
                    </Link>
                    <div className="flex items-center gap-2 text-sm">
                      {wf.pos && <span className="text-gray-500 dark:text-gray-400">{wf.pos}</span>}
                      {wf.ur && <span dir="rtl" lang="ur" className="font-nastaliq text-base">{wf.ur}</span>}
                    </div>
                  </div>
                ))}
              </div>
            </section>
          )}

          {/* See Also */}
          {(word.related_words?.see_also?.length ?? 0) > 0 && (
            <section className="p-5 bg-white dark:bg-gray-900 rounded-2xl border border-gray-200 dark:border-gray-700">
              <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 mb-3">See Also</h2>
              <div className="flex flex-wrap gap-2">
                {word.related_words!.see_also!.map((w) => (
                  <PillTag key={w} href={`/word/${encodeURIComponent(w.toLowerCase())}`}>{w}</PillTag>
                ))}
              </div>
            </section>
          )}
        </div>

        {/* Memory Tip */}
        {word.memory_tip && (
          <section className="p-5 bg-amber-50 dark:bg-amber-950 rounded-2xl border border-amber-200 dark:border-amber-800 mb-6">
            <h2 className="text-base font-semibold text-amber-900 dark:text-amber-100 mb-2">💡 Memory Tip</h2>
            {word.memory_tip.mnemonic && (
              <p className="text-amber-800 dark:text-amber-200 text-sm mb-1">{word.memory_tip.mnemonic}</p>
            )}
            {word.memory_tip.visual_association && (
              <p className="text-amber-700 dark:text-amber-300 text-sm italic">{word.memory_tip.visual_association}</p>
            )}
          </section>
        )}

        {/* Urdu Poetry */}
        {word.urdu_poetry && (
          <section className="p-5 bg-purple-50 dark:bg-purple-950 rounded-2xl border border-purple-200 dark:border-purple-800 mb-6">
            <h2 className="text-base font-semibold text-purple-900 dark:text-purple-100 mb-3">✍️ Urdu Poetry</h2>
            {word.urdu_poetry.couplet_ur && (
              <p dir="rtl" lang="ur" className="font-nastaliq text-2xl text-purple-800 dark:text-purple-200 mb-2">
                {word.urdu_poetry.couplet_ur}
              </p>
            )}
            {word.urdu_poetry.couplet_roman && (
              <p className="text-sm text-purple-700 dark:text-purple-300 italic mb-2">
                {word.urdu_poetry.couplet_roman}
              </p>
            )}
            {word.urdu_poetry.translation_en && (
              <p className="text-sm text-purple-700 dark:text-purple-300 mb-2">
                {word.urdu_poetry.translation_en}
              </p>
            )}
            {word.urdu_poetry.poet && (
              <p className="text-xs text-purple-500 dark:text-purple-400">
                — {word.urdu_poetry.poet}
                {word.urdu_poetry.source ? `, ${word.urdu_poetry.source}` : ""}
              </p>
            )}
            {word.urdu_poetry.ai_generated && (
              <p className="text-xs text-purple-400 dark:text-purple-500 mt-2 italic">
                * Poetry attribution is AI-generated and may require verification.
              </p>
            )}
          </section>
        )}

        {/* Urdu Proverb */}
        {word.urdu_proverb && (
          <section className="p-5 bg-teal-50 dark:bg-teal-950 rounded-2xl border border-teal-200 dark:border-teal-800 mb-6">
            <h2 className="text-base font-semibold text-teal-900 dark:text-teal-100 mb-3">🗣️ Urdu Proverb</h2>
            {word.urdu_proverb.proverb_ur && (
              <p dir="rtl" lang="ur" className="font-nastaliq text-xl text-teal-800 dark:text-teal-200 mb-1">
                {word.urdu_proverb.proverb_ur}
              </p>
            )}
            {word.urdu_proverb.proverb_roman && (
              <p className="text-sm text-teal-700 dark:text-teal-300 italic mb-1">
                {word.urdu_proverb.proverb_roman}
              </p>
            )}
            {word.urdu_proverb.translation_en && (
              <p className="text-sm text-teal-700 dark:text-teal-300">{word.urdu_proverb.translation_en}</p>
            )}
          </section>
        )}

        {/* Islamic Reference */}
        {word.islamic_reference && (
          <section className="p-5 bg-green-50 dark:bg-green-950 rounded-2xl border border-green-200 dark:border-green-800 mb-6">
            <h2 className="text-base font-semibold text-green-900 dark:text-green-100 mb-3">
              ☽ Islamic Reference
            </h2>
            {word.islamic_reference.reference && (
              <p className="text-xs font-medium text-green-600 dark:text-green-400 mb-2">
                {word.islamic_reference.type} — {word.islamic_reference.reference}
              </p>
            )}
            {word.islamic_reference.text_ar && (
              <p dir="rtl" lang="ar" className="font-nastaliq text-xl text-green-800 dark:text-green-200 mb-1">
                {word.islamic_reference.text_ar}
              </p>
            )}
            {word.islamic_reference.translation_en && (
              <p className="text-sm text-green-700 dark:text-green-300">{word.islamic_reference.translation_en}</p>
            )}
          </section>
        )}

        {/* Etymology */}
        {word.etymology && (
          <section className="p-5 bg-white dark:bg-gray-900 rounded-2xl border border-gray-200 dark:border-gray-700 mb-6">
            <h2 className="text-base font-semibold text-gray-900 dark:text-gray-100 mb-3">📖 Etymology</h2>
            {word.etymology.origin_language && (
              <p className="text-sm text-gray-600 dark:text-gray-400">
                <span className="font-medium">Origin:</span>{" "}
                {word.etymology.origin_language}
                {word.etymology.origin_word ? ` "${word.etymology.origin_word}"` : ""}
                {word.etymology.origin_meaning ? ` — ${word.etymology.origin_meaning}` : ""}
              </p>
            )}
            {word.etymology.first_known_use && (
              <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
                <span className="font-medium">First known use:</span> {word.etymology.first_known_use}
              </p>
            )}
            {word.etymology.history && (
              <p className="text-sm text-gray-700 dark:text-gray-300 mt-2">{word.etymology.history}</p>
            )}
          </section>
        )}
      </main>
    </>
  );
}
