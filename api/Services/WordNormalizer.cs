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

        if (Lemmas.TryGetValue(normalized, out var lemma))
            return lemma;

        // Basic suffix stripping for plurals
        if (normalized.Length > 4 && normalized.EndsWith("ing"))
        {
            var stem = normalized[..^3];
            if (stem.Length >= 3) return stem;
        }
        if (normalized.Length > 3 && normalized.EndsWith("es") && !normalized.EndsWith("ies"))
        {
            var stem = normalized[..^2];
            if (stem.Length >= 3) return stem;
        }
        if (normalized.Length > 3 && normalized.EndsWith("s") && !normalized.EndsWith("ss"))
        {
            var stem = normalized[..^1];
            if (stem.Length >= 3) return stem;
        }

        return normalized;
    }
}
