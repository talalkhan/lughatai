using System.Security.Claims;
using System.Text.RegularExpressions;
using UrduMeaning.Api.BackgroundJobs;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Models;

namespace UrduMeaning.Api.Services;

public interface IWordService
{
    Task<WordData?> GetWordAsync(string word, int? userId = null);
    Task<WordData?> GetWordOfTheDayAsync();
    Task<WordData?> GetRandomWordAsync(string? difficulty);
}

public class WordService : IWordService
{
    private static readonly Regex LiveGenerationWordPattern = new(@"^[a-z]+$", RegexOptions.Compiled);
    private readonly ICacheService _cache;
    private readonly IWordRepository _repo;
    private readonly IWordAIService _ai;
    private readonly IWordNormalizer _normalizer;
    private readonly IWordEnrichmentQueue _enrichmentQueue;
    private readonly ILogger<WordService> _logger;
    private readonly IConfiguration _config;

    public WordService(
        ICacheService cache,
        IWordRepository repo,
        IWordAIService ai,
        IWordNormalizer normalizer,
        IWordEnrichmentQueue enrichmentQueue,
        ILogger<WordService> logger,
        IConfiguration config)
    {
        _cache = cache;
        _repo = repo;
        _ai = ai;
        _normalizer = normalizer;
        _enrichmentQueue = enrichmentQueue;
        _logger = logger;
        _config = config;
    }

    public async Task<WordData?> GetWordAsync(string rawWord, int? userId = null)
    {
        var word = _normalizer.Normalize(rawWord);
        if (string.IsNullOrEmpty(word)) return null;

        WordData? result = null;

        // L1: Redis
        var cached = await _cache.GetWordAsync(word);
        if (cached != null)
        {
            _ = _repo.IncrementLookupCountAsync(word);
            result = cached;
        }
        else
        {
            // L2: Postgres
            var stored = await _repo.GetWordAsync(word);
            if (stored != null)
            {
                _ = _cache.SetWordAsync(word, stored);
                _ = _repo.IncrementLookupCountAsync(word);
                result = stored;
            }
            else
            {
                // L3: AI generation.
                // Only clean single English tokens can trigger live AI generation. Bots crawl
                // phrase and repeatedly encoded URLs like /word/matrix%20calculation or
                // /word/math%252520system; those should never spend AI credits.
                if (!CanGenerateLive(rawWord, word))
                    return null;

                // Master kill switch — set WordGeneration__Enabled=false in Azure to stop all
                // new word generation without a deployment (e.g. to protect API credits).
                if (!_config.GetValue<bool>("WordGeneration:Enabled", true))
                    return null;

                // Deterministic validity gate: live generation only runs for words
                // in approved_words. This table is the durable whitelist; word_queue
                // is operational batch state and may be empty in production.
                if (_config.GetValue<bool>("WordGeneration:RequireApprovedWord", true)
                    && !await _repo.IsApprovedWordAsync(word))
                {
                    _logger.LogInformation("Skipped live generation for unapproved word '{Word}'", word);
                    return null;
                }

                try
                {
                    var generated = await _ai.GenerateWordAsync(word, usePremium: true);
                    await _repo.SaveWordAsync(word, generated);
                    _ = _cache.SetWordAsync(word, generated);
                    _ = _repo.IncrementLookupCountAsync(word);
                    result = generated;
                }
                catch (AIServiceException ex)
                {
                    _logger.LogError(ex, "AI service failed for word '{Word}'", word);
                    return null;
                }
            }
        }

        if (WordEnrichmentProcessor.NeedsEnrichment(result))
            _enrichmentQueue.TryEnqueue(word);

        // Record history for authenticated users (fire-and-forget)
        if (result != null && userId.HasValue)
            _ = _repo.RecordHistoryAsync(userId.Value, word);

        return result;
    }

    public async Task<WordData?> GetWordOfTheDayAsync()
    {
        return await _repo.GetWordOfTheDayAsync();
    }

    public async Task<WordData?> GetRandomWordAsync(string? difficulty)
    {
        return await _repo.GetRandomWordAsync(difficulty);
    }

    public static bool CanGenerateLive(string rawWord, string normalizedWord)
    {
        if (string.IsNullOrWhiteSpace(rawWord) || string.IsNullOrWhiteSpace(normalizedWord))
            return false;

        if (rawWord.Contains('%') || rawWord.Contains('+'))
            return false;

        if (rawWord.Any(char.IsWhiteSpace) || normalizedWord.Any(char.IsWhiteSpace))
            return false;

        return LiveGenerationWordPattern.IsMatch(normalizedWord);
    }
}
