using System.Text.Json.Serialization;

namespace LughatAI.Api.Models;

public class WordData
{
    [JsonPropertyName("word")]
    public string Word { get; set; } = "";

    [JsonPropertyName("phonetic")]
    public Phonetic? Phonetic { get; set; }

    [JsonPropertyName("audio")]
    public Audio? Audio { get; set; }

    [JsonPropertyName("learning")]
    public Learning? Learning { get; set; }

    [JsonPropertyName("etymology")]
    public Etymology? Etymology { get; set; }

    [JsonPropertyName("script_variants")]
    public ScriptVariants? ScriptVariants { get; set; }

    [JsonPropertyName("meanings")]
    public List<Meaning> Meanings { get; set; } = new();

    [JsonPropertyName("word_family")]
    public List<WordFamilyEntry> WordFamily { get; set; } = new();

    [JsonPropertyName("related_words")]
    public RelatedWords? RelatedWords { get; set; }

    [JsonPropertyName("memory_tip")]
    public MemoryTip? MemoryTip { get; set; }

    [JsonPropertyName("urdu_poetry")]
    public UrduPoetry? UrduPoetry { get; set; }

    [JsonPropertyName("urdu_proverb")]
    public UrduProverb? UrduProverb { get; set; }

    [JsonPropertyName("islamic_reference")]
    public IslamicReference? IslamicReference { get; set; }

    [JsonPropertyName("_meta")]
    public MetaInfo? Meta { get; set; }
}

public class Phonetic
{
    [JsonPropertyName("ipa")]
    public string? Ipa { get; set; }

    [JsonPropertyName("syllables")]
    public string? Syllables { get; set; }

    [JsonPropertyName("stress")]
    public string? Stress { get; set; }
}

public class Audio
{
    [JsonPropertyName("en_url")]
    public string? EnUrl { get; set; }

    [JsonPropertyName("ur_url")]
    public string? UrUrl { get; set; }
}

public class Learning
{
    [JsonPropertyName("difficulty")]
    public string? Difficulty { get; set; }

    [JsonPropertyName("cefr_level")]
    public string? CefrLevel { get; set; }

    [JsonPropertyName("frequency_rank")]
    public int? FrequencyRank { get; set; }

    [JsonPropertyName("contexts")]
    public List<string> Contexts { get; set; } = new();

    [JsonPropertyName("sentiment")]
    public string? Sentiment { get; set; }

    [JsonPropertyName("emoji")]
    public string? Emoji { get; set; }
}

public class Etymology
{
    [JsonPropertyName("origin_language")]
    public string? OriginLanguage { get; set; }

    [JsonPropertyName("origin_word")]
    public string? OriginWord { get; set; }

    [JsonPropertyName("origin_meaning")]
    public string? OriginMeaning { get; set; }

    [JsonPropertyName("history")]
    public string? History { get; set; }

    [JsonPropertyName("first_known_use")]
    public string? FirstKnownUse { get; set; }
}

public class ScriptVariants
{
    [JsonPropertyName("nastaliq")]
    public string? Nastaliq { get; set; }

    [JsonPropertyName("roman_urdu")]
    public string? RomanUrdu { get; set; }

    [JsonPropertyName("devanagari")]
    public string? Devanagari { get; set; }
}

public class Meaning
{
    [JsonPropertyName("pos")]
    public string? Pos { get; set; }

    [JsonPropertyName("register")]
    public string? Register { get; set; }

    [JsonPropertyName("definition_en")]
    public string? DefinitionEn { get; set; }

    [JsonPropertyName("definition_ur")]
    public string? DefinitionUr { get; set; }

    [JsonPropertyName("translations")]
    public Translations? Translations { get; set; }

    [JsonPropertyName("synonyms")]
    public Synonyms? Synonyms { get; set; }

    [JsonPropertyName("antonyms")]
    public Antonyms? Antonyms { get; set; }

    [JsonPropertyName("collocations")]
    public List<string> Collocations { get; set; } = new();

    [JsonPropertyName("examples")]
    public List<Example> Examples { get; set; } = new();

    [JsonPropertyName("confusables")]
    public List<Confusable> Confusables { get; set; } = new();
}

public class Translations
{
    [JsonPropertyName("primary")]
    public string? Primary { get; set; }

    [JsonPropertyName("primary_roman")]
    public string? PrimaryRoman { get; set; }

    [JsonPropertyName("alternatives")]
    public List<string> Alternatives { get; set; } = new();

    [JsonPropertyName("alternatives_roman")]
    public List<string> AlternativesRoman { get; set; } = new();

    [JsonPropertyName("formal")]
    public string? Formal { get; set; }

    [JsonPropertyName("colloquial")]
    public string? Colloquial { get; set; }
}

public class Synonyms
{
    [JsonPropertyName("en")]
    public List<string> En { get; set; } = new();

    [JsonPropertyName("ur")]
    public List<string> Ur { get; set; } = new();

    [JsonPropertyName("ur_roman")]
    public List<string> UrRoman { get; set; } = new();
}

public class Antonyms
{
    [JsonPropertyName("en")]
    public List<string> En { get; set; } = new();

    [JsonPropertyName("ur")]
    public List<string> Ur { get; set; } = new();

    [JsonPropertyName("ur_roman")]
    public List<string> UrRoman { get; set; } = new();
}

public class Example
{
    [JsonPropertyName("en")]
    public string? En { get; set; }

    [JsonPropertyName("ur")]
    public string? Ur { get; set; }

    [JsonPropertyName("roman")]
    public string? Roman { get; set; }
}

public class Confusable
{
    [JsonPropertyName("word")]
    public string? Word { get; set; }

    [JsonPropertyName("difference")]
    public string? Difference { get; set; }
}

public class WordFamilyEntry
{
    [JsonPropertyName("word")]
    public string? Word { get; set; }

    [JsonPropertyName("pos")]
    public string? Pos { get; set; }

    [JsonPropertyName("ur")]
    public string? Ur { get; set; }
}

public class RelatedWords
{
    [JsonPropertyName("see_also")]
    public List<string> SeeAlso { get; set; } = new();

    [JsonPropertyName("thematic_group")]
    public List<string> ThematicGroup { get; set; } = new();
}

public class MemoryTip
{
    [JsonPropertyName("mnemonic")]
    public string? Mnemonic { get; set; }

    [JsonPropertyName("visual_association")]
    public string? VisualAssociation { get; set; }
}

public class UrduPoetry
{
    [JsonPropertyName("couplet_ur")]
    public string? CoupletUr { get; set; }

    [JsonPropertyName("couplet_roman")]
    public string? CoupletRoman { get; set; }

    [JsonPropertyName("translation_en")]
    public string? TranslationEn { get; set; }

    [JsonPropertyName("poet")]
    public string? Poet { get; set; }

    [JsonPropertyName("source")]
    public string? Source { get; set; }

    [JsonPropertyName("ai_generated")]
    public bool AiGenerated { get; set; }
}

public class UrduProverb
{
    [JsonPropertyName("proverb_ur")]
    public string? ProverbUr { get; set; }

    [JsonPropertyName("proverb_roman")]
    public string? ProverbRoman { get; set; }

    [JsonPropertyName("translation_en")]
    public string? TranslationEn { get; set; }
}

public class IslamicReference
{
    [JsonPropertyName("type")]
    public string? Type { get; set; }

    [JsonPropertyName("reference")]
    public string? Reference { get; set; }

    [JsonPropertyName("text_ar")]
    public string? TextAr { get; set; }

    [JsonPropertyName("text_ur")]
    public string? TextUr { get; set; }

    [JsonPropertyName("translation_en")]
    public string? TranslationEn { get; set; }
}

public class MetaInfo
{
    [JsonPropertyName("generated_by")]
    public string? GeneratedBy { get; set; }

    [JsonPropertyName("generated_at")]
    public string? GeneratedAt { get; set; }

    [JsonPropertyName("model")]
    public string? Model { get; set; }

    [JsonPropertyName("stage")]
    public string? Stage { get; set; }

    [JsonPropertyName("version")]
    public string? Version { get; set; }

    [JsonPropertyName("reviewed")]
    public bool Reviewed { get; set; }
}
