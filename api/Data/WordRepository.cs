using Dapper;
using LughatAI.Api.Models;
using Npgsql;
using System.Text.Json;

namespace LughatAI.Api.Data;

public interface IWordRepository
{
    Task<WordData?> GetWordAsync(string wordLower);
    Task SaveWordAsync(string word, WordData data);
    Task IncrementLookupCountAsync(string wordLower);
    Task<IEnumerable<SearchResult>> SearchAsync(string prefix, int limit);
    Task<IEnumerable<WordSummary>> BrowseAsync(string? context, string? difficulty, string? cefr, int page, int limit);
    Task<int> BrowseTotalAsync(string? context, string? difficulty, string? cefr);
    Task<WordData?> GetWordOfTheDayAsync();
    Task<WordData?> GetRandomWordAsync(string? difficulty);
    Task UpdateAudioUrlAsync(string wordLower, string lang, string url);
    Task<IEnumerable<SearchResult>> SearchByRomanUrduAsync(string query, int limit);
    Task RecordHistoryAsync(int userId, string word);
    Task AddCorrectionAsync(string word, int? userId, string reason, string? notes);
    Task<IEnumerable<dynamic>> GetOpenCorrectionsAsync();
    Task<IEnumerable<dynamic>> GetUnverifiedPoetryAsync();
    Task MarkPoetryVerifiedAsync(string wordLower);
    Task<QueueStatus> GetQueueStatusAsync();
    Task AddToQueueAsync(IEnumerable<string> words, int priority = 3);
    Task RetryFailedAsync();
    Task<IEnumerable<WordQueue>> GetPendingBatchAsync(int count);
    Task SetQueueStatusAsync(int id, string status, string? errorMessage = null);
    Task IncrementQueueAttemptsAsync(int id, string? errorMessage = null);
    Task ResetToPendingAsync(int id, string? errorMessage = null);
}

public record SearchResult(string Word, string? Urdu, string? Difficulty);
public record WordSummary(string Word, string? Urdu, string? Difficulty, string? DefinitionEn, string? Emoji);
public record QueueStatus(int Pending, int Processing, int Done, int Failed);

public class WordRepository : IWordRepository
{
    private readonly IConfiguration _config;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public WordRepository(IConfiguration config)
    {
        _config = config;
    }

    private NpgsqlConnection Connection() =>
        new(_config.GetConnectionString("Default"));

    public async Task<WordData?> GetWordAsync(string wordLower)
    {
        using var conn = Connection();
        var sql = "SELECT data FROM word_definitions WHERE word_lower = @wordLower LIMIT 1";
        var json = await conn.QuerySingleOrDefaultAsync<string>(sql, new { wordLower });
        if (json == null) return null;
        return JsonSerializer.Deserialize<WordData>(json, JsonOpts);
    }

    public async Task SaveWordAsync(string word, WordData data)
    {
        using var conn = Connection();
        var json = JsonSerializer.Serialize(data, JsonOpts);
        var sql = """
            INSERT INTO word_definitions (word, data)
            VALUES (@word, @data::jsonb)
            ON CONFLICT (word_lower) DO UPDATE
            SET data = @data::jsonb, updated_at = now()
            """;
        await conn.ExecuteAsync(sql, new { word, data = json });
    }

    public async Task IncrementLookupCountAsync(string wordLower)
    {
        using var conn = Connection();
        var sql = "UPDATE word_definitions SET lookup_count = lookup_count + 1, updated_at = now() WHERE word_lower = @wordLower";
        await conn.ExecuteAsync(sql, new { wordLower });
    }

    public async Task<IEnumerable<SearchResult>> SearchAsync(string prefix, int limit)
    {
        using var conn = Connection();
        var sql = """
            SELECT word, data->'script_variants'->>'nastaliq' as urdu,
                   data->'learning'->>'difficulty' as difficulty
            FROM word_definitions
            WHERE word_lower LIKE @prefix
            ORDER BY lookup_count DESC
            LIMIT @limit
            """;
        return await conn.QueryAsync<SearchResult>(sql, new { prefix = prefix + "%", limit });
    }

    public async Task<IEnumerable<WordSummary>> BrowseAsync(string? context, string? difficulty, string? cefr, int page, int limit)
    {
        using var conn = Connection();
        var (where, parameters) = BuildBrowseFilter(context, difficulty, cefr);
        var offset = (page - 1) * limit;
        var sql = $"""
            SELECT word,
                   data->'script_variants'->>'nastaliq' as urdu,
                   data->'learning'->>'difficulty' as difficulty,
                   data->'meanings'->0->>'definition_en' as definitionEn,
                   data->'learning'->>'emoji' as emoji
            FROM word_definitions
            {where}
            ORDER BY lookup_count DESC
            LIMIT @limit OFFSET @offset
            """;
        parameters.Add("limit", limit);
        parameters.Add("offset", offset);
        return await conn.QueryAsync<WordSummary>(sql, parameters);
    }

    public async Task<int> BrowseTotalAsync(string? context, string? difficulty, string? cefr)
    {
        using var conn = Connection();
        var (where, parameters) = BuildBrowseFilter(context, difficulty, cefr);
        var sql = $"SELECT COUNT(*) FROM word_definitions {where}";
        return await conn.QuerySingleAsync<int>(sql, parameters);
    }

    private static (string Where, DynamicParameters Params) BuildBrowseFilter(string? context, string? difficulty, string? cefr)
    {
        var conditions = new List<string>();
        var p = new DynamicParameters();
        if (!string.IsNullOrEmpty(context))
        {
            conditions.Add("data->'learning'->'contexts' @> @ctx::jsonb");
            p.Add("ctx", $"[\"{context}\"]");
        }
        if (!string.IsNullOrEmpty(difficulty))
        {
            conditions.Add("data->'learning'->>'difficulty' = @difficulty");
            p.Add("difficulty", difficulty);
        }
        if (!string.IsNullOrEmpty(cefr))
        {
            conditions.Add("data->'learning'->>'cefr_level' = @cefr");
            p.Add("cefr", cefr);
        }
        var where = conditions.Count > 0 ? "WHERE " + string.Join(" AND ", conditions) : "";
        return (where, p);
    }

    public async Task<WordData?> GetWordOfTheDayAsync()
    {
        using var conn = Connection();
        var sql = """
            SELECT data FROM word_definitions
            ORDER BY MD5(word || 'lughatai_wotd_salt' || CURRENT_DATE::text)
            LIMIT 1
            """;
        var json = await conn.QuerySingleOrDefaultAsync<string>(sql);
        if (json == null) return null;
        return JsonSerializer.Deserialize<WordData>(json, JsonOpts);
    }

    public async Task<WordData?> GetRandomWordAsync(string? difficulty)
    {
        using var conn = Connection();
        string sql;
        object param;
        if (!string.IsNullOrEmpty(difficulty))
        {
            sql = "SELECT data FROM word_definitions WHERE data->'learning'->>'difficulty' = @difficulty ORDER BY RANDOM() LIMIT 1";
            param = new { difficulty };
        }
        else
        {
            sql = "SELECT data FROM word_definitions ORDER BY RANDOM() LIMIT 1";
            param = new { };
        }
        var json = await conn.QuerySingleOrDefaultAsync<string>(sql, param);
        if (json == null) return null;
        return JsonSerializer.Deserialize<WordData>(json, JsonOpts);
    }

    public async Task<IEnumerable<SearchResult>> SearchByRomanUrduAsync(string query, int limit)
    {
        using var conn = Connection();
        // Match words whose stored roman_urdu starts with the query (case-insensitive LIKE)
        var sql = """
            SELECT word,
                   data->'script_variants'->>'nastaliq' as urdu,
                   data->'learning'->>'difficulty' as difficulty
            FROM word_definitions
            WHERE lower(data->'script_variants'->>'roman_urdu') LIKE @prefix
            ORDER BY lookup_count DESC
            LIMIT @limit
            """;
        return await conn.QueryAsync<SearchResult>(sql, new { prefix = query + "%", limit });
    }

    public async Task RecordHistoryAsync(int userId, string word)
    {
        using var conn = Connection();
        // Upsert: if the word was already looked up today, update the timestamp
        await conn.ExecuteAsync(
            "INSERT INTO user_history (user_id, word) VALUES (@userId, @word)",
            new { userId, word = word.ToLowerInvariant() });

        // Trim to last 100 entries per user
        await conn.ExecuteAsync("""
            DELETE FROM user_history
            WHERE id IN (
                SELECT id FROM user_history
                WHERE user_id = @userId
                ORDER BY looked_up_at DESC
                OFFSET 100
            )
            """, new { userId });
    }

    public async Task AddCorrectionAsync(string word, int? userId, string reason, string? notes)
    {
        using var conn = Connection();
        await conn.ExecuteAsync(
            "INSERT INTO corrections (word, user_id, reason, notes) VALUES (@word, @userId, @reason, @notes)",
            new { word = word.ToLowerInvariant(), userId, reason, notes });
    }

    public async Task<IEnumerable<dynamic>> GetOpenCorrectionsAsync()
    {
        using var conn = Connection();
        return await conn.QueryAsync(
            "SELECT id, word, user_id, reason, notes, status, created_at FROM corrections WHERE status = 'open' ORDER BY created_at DESC LIMIT 100");
    }

    public async Task<IEnumerable<dynamic>> GetUnverifiedPoetryAsync()
    {
        using var conn = Connection();
        var sql = """
            SELECT word,
                   data->'urdu_poetry'->>'poet' as poet,
                   data->'urdu_poetry'->>'couplet_ur' as couplet_ur,
                   data->'urdu_poetry'->>'translation_en' as translation_en,
                   (data->'urdu_poetry'->>'ai_generated')::boolean as ai_generated
            FROM word_definitions
            WHERE data->'urdu_poetry' IS NOT NULL
              AND (data->'_meta'->>'reviewed')::boolean IS NOT TRUE
            ORDER BY word
            LIMIT 50
            """;
        return await conn.QueryAsync(sql);
    }

    public async Task MarkPoetryVerifiedAsync(string wordLower)
    {
        using var conn = Connection();
        await conn.ExecuteAsync("""
            UPDATE word_definitions
            SET data = jsonb_set(data, '{_meta,reviewed}', 'true'::jsonb),
                updated_at = now()
            WHERE word_lower = @wordLower
            """, new { wordLower });
    }

    public async Task UpdateAudioUrlAsync(string wordLower, string lang, string url)
    {
        using var conn = Connection();
        // jsonb_set path: {audio, en_url} or {audio, ur_url}
        var field = lang == "en" ? "en_url" : "ur_url";
        var sql = $$"""
            UPDATE word_definitions
            SET data = jsonb_set(data, '{audio,{{field}}}', @urlJson::jsonb, true),
                updated_at = now()
            WHERE word_lower = @wordLower
            """;
        await conn.ExecuteAsync(sql, new { wordLower, urlJson = $"\"{url}\"" });
    }

    public async Task<QueueStatus> GetQueueStatusAsync()
    {
        using var conn = Connection();
        var sql = """
            SELECT
                COUNT(*) FILTER (WHERE status = 'pending')::int    as pending,
                COUNT(*) FILTER (WHERE status = 'processing')::int as processing,
                COUNT(*) FILTER (WHERE status = 'done')::int       as done,
                COUNT(*) FILTER (WHERE status = 'failed')::int     as failed
            FROM word_queue
            """;
        return await conn.QuerySingleAsync<QueueStatus>(sql);
    }

    public async Task AddToQueueAsync(IEnumerable<string> words, int priority = 3)
    {
        using var conn = Connection();
        var sql = "INSERT INTO word_queue (word, priority) VALUES (@word, @priority) ON CONFLICT (word) DO NOTHING";
        await conn.ExecuteAsync(sql, words.Select(w => new { word = w.Trim().ToLowerInvariant(), priority }));
    }

    public async Task RetryFailedAsync()
    {
        using var conn = Connection();
        var sql = "UPDATE word_queue SET status = 'pending', attempts = 0, error_message = NULL, updated_at = now() WHERE status = 'failed'";
        await conn.ExecuteAsync(sql);
    }

    public async Task<IEnumerable<WordQueue>> GetPendingBatchAsync(int count)
    {
        using var conn = Connection();
        var sql = """
            SELECT id, word, status, priority, attempts, error_message as errormessage, created_at as createdat, updated_at as updatedat
            FROM word_queue
            WHERE status = 'pending'
            ORDER BY priority ASC, id ASC
            LIMIT @count
            FOR UPDATE SKIP LOCKED
            """;
        return await conn.QueryAsync<WordQueue>(sql, new { count });
    }

    public async Task SetQueueStatusAsync(int id, string status, string? errorMessage = null)
    {
        using var conn = Connection();
        var sql = "UPDATE word_queue SET status = @status, error_message = @errorMessage, updated_at = now() WHERE id = @id";
        await conn.ExecuteAsync(sql, new { id, status, errorMessage });
    }

    public async Task IncrementQueueAttemptsAsync(int id, string? errorMessage = null)
    {
        using var conn = Connection();
        var sql = """
            UPDATE word_queue
            SET attempts = attempts + 1,
                status = CASE WHEN attempts + 1 >= 3 THEN 'failed' ELSE 'pending' END,
                error_message = @errorMessage,
                updated_at = now()
            WHERE id = @id
            """;
        await conn.ExecuteAsync(sql, new { id, errorMessage });
    }

    // Reset a word back to pending without burning an attempt.
    // Used for transient errors like rate limits where the word is fine
    // but we just need to wait before retrying.
    public async Task ResetToPendingAsync(int id, string? errorMessage = null)
    {
        using var conn = Connection();
        var sql = """
            UPDATE word_queue
            SET status = 'pending',
                error_message = @errorMessage,
                updated_at = now()
            WHERE id = @id
            """;
        await conn.ExecuteAsync(sql, new { id, errorMessage });
    }
}
