using System.Text.RegularExpressions;

namespace UrduMeaning.Api.Services;

public interface IWordNormalizer
{
    string Normalize(string word);
}

public class WordNormalizer : IWordNormalizer
{
    private static readonly Regex AllowedChars = new(@"[^a-zA-Z\s\-']", RegexOptions.Compiled);
    private static readonly Regex TrailingPunctuation = new(@"[^\w\s]+$", RegexOptions.Compiled);

    private static readonly Dictionary<string, string> Lemmas = new(StringComparer.OrdinalIgnoreCase)
    {
        // Common inflections
        { "running", "run" }, { "runs", "run" }, { "ran", "run" },
        { "swimming", "swim" }, { "swims", "swim" }, { "swam", "swim" },
        { "eating", "eat" }, { "eats", "eat" }, { "ate", "eat" },
        { "going", "go" }, { "goes", "go" }, { "went", "go" },
        { "making", "make" }, { "makes", "make" }, { "made", "make" },
        { "taking", "take" }, { "takes", "take" }, { "took", "take" },
        { "coming", "come" }, { "comes", "come" }, { "came", "come" },
        { "seeing", "see" }, { "sees", "see" }, { "saw", "see" },
        { "thinking", "think" }, { "thinks", "think" }, { "thought", "think" },
        { "knowing", "know" }, { "knows", "know" }, { "knew", "know" },
        { "getting", "get" }, { "gets", "get" }, { "got", "get" },
    };

    public string Normalize(string word)
    {
        if (string.IsNullOrWhiteSpace(word))
            return string.Empty;

        var normalized = word.Trim();
        normalized = TrailingPunctuation.Replace(normalized, "");
        normalized = normalized.ToLowerInvariant();
        normalized = AllowedChars.Replace(normalized, "");
        normalized = normalized.Trim();

        // Only map explicitly known inflections — suffix stripping was removed
        // because it incorrectly mutilated adjectives/nouns ending in -ous, -us,
        // -is, -ness, etc. (e.g. "capacious" → "capaciou"). The Lemmas table
        // covers the common verb forms that actually matter.
        if (Lemmas.TryGetValue(normalized, out var lemma))
            return lemma;

        return normalized;
    }
}
