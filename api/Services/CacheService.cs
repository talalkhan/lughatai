using System.Text.Json;
using UrduMeaning.Api.Models;
using StackExchange.Redis;

namespace UrduMeaning.Api.Services;

public interface ICacheService
{
    Task<WordData?> GetWordAsync(string word);
    Task SetWordAsync(string word, WordData data);
    Task InvalidateWordAsync(string word);
}

public class CacheService : ICacheService
{
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<CacheService> _logger;
    private static readonly JsonSerializerOptions JsonOpts = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };

    public CacheService(IConnectionMultiplexer redis, ILogger<CacheService> logger)
    {
        _redis = redis;
        _logger = logger;
    }

    public async Task<WordData?> GetWordAsync(string word)
    {
        try
        {
            var db = _redis.GetDatabase();
            var value = await db.StringGetAsync(CacheKey(word));
            if (value.IsNullOrEmpty)
                return null;
            return JsonSerializer.Deserialize<WordData>(value!, JsonOpts);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis get failed for word '{Word}', falling through to DB", word);
            return null;
        }
    }

    public async Task SetWordAsync(string word, WordData data)
    {
        try
        {
            var db = _redis.GetDatabase();
            var json = JsonSerializer.Serialize(data, JsonOpts);
            await db.StringSetAsync(CacheKey(word), json);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis set failed for word '{Word}'", word);
        }
    }

    public async Task InvalidateWordAsync(string word)
    {
        try
        {
            var db = _redis.GetDatabase();
            await db.KeyDeleteAsync(CacheKey(word));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis delete failed for word '{Word}'", word);
        }
    }

    private static string CacheKey(string word) => $"word:{word}";
}
