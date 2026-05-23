using System.Security.Claims;
using LughatAI.Api.Data;
using LughatAI.Api.Models;

namespace LughatAI.Api.Services;

public interface IWordService
{
    Task<WordData?> GetWordAsync(string word, int? userId = null);
    Task<WordData?> GetWordOfTheDayAsync();
    Task<WordData?> GetRandomWordAsync(string? difficulty);
}

public class WordService : IWordService
{
    private readonly ICacheService _cache;
    private readonly IWordRepository _repo;
    private readonly IWordAIService _ai;
    private readonly IWordNormalizer _normalizer;
    private readonly ILogger<WordService> _logger;

    public WordService(
        ICacheService cache,
        IWordRepository repo,
        IWordAIService ai,
        IWordNormalizer normalizer,
        ILogger<WordService> logger)
    {
        _cache = cache;
        _repo = repo;
        _ai = ai;
        _normalizer = normalizer;
        _logger = logger;
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
                // L3: AI generation
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
}
