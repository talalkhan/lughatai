using System.Security.Claims;
using Dapper;
using UrduMeaning.Api.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api/user")]
[Authorize]
public class UserController : ControllerBase
{
    private readonly IConfiguration _config;
    private readonly IWordService _wordService;

    public UserController(IConfiguration config, IWordService wordService)
    {
        _config = config;
        _wordService = wordService;
    }

    private NpgsqlConnection Connection() => new(_config.GetConnectionString("Default"));

    private int? CurrentUserId =>
        int.TryParse(User.FindFirstValue(ClaimTypes.NameIdentifier), out var userId) ? userId : null;

    // ── Favorites ────────────────────────────────────────────────────────────

    [HttpGet("favorites")]
    public async Task<IActionResult> GetFavorites()
    {
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        var sql = """
            SELECT uf.word,
                   wd.data->'script_variants'->>'nastaliq' as urdu,
                   wd.data->'learning'->>'difficulty' as difficulty,
                   wd.data->'meanings'->0->>'definition_en' as definition_en,
                   wd.data->'learning'->>'emoji' as emoji,
                   uf.created_at
            FROM user_favorites uf
            LEFT JOIN word_definitions wd ON wd.word_lower = lower(uf.word)
            WHERE uf.user_id = @userId
            ORDER BY uf.created_at DESC
            """;
        var results = await conn.QueryAsync(sql, new { userId });
        return Ok(results);
    }

    [HttpPost("favorites/{word}")]
    public async Task<IActionResult> AddFavorite(string word)
    {
        if (string.IsNullOrWhiteSpace(word) || word.Length > 150)
            return BadRequest(new { error = "Invalid word" });
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        try
        {
            await conn.ExecuteAsync(
                "INSERT INTO user_favorites (user_id, word) VALUES (@userId, @word) ON CONFLICT DO NOTHING",
                new { userId, word = word.Trim().ToLowerInvariant() });
            return Ok(new { favorited = true });
        }
        catch
        {
            return StatusCode(500, new { error = "Could not save favorite" });
        }
    }

    [HttpDelete("favorites/{word}")]
    public async Task<IActionResult> RemoveFavorite(string word)
    {
        if (string.IsNullOrWhiteSpace(word) || word.Length > 150)
            return BadRequest(new { error = "Invalid word" });
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        var affected = await conn.ExecuteAsync(
            "DELETE FROM user_favorites WHERE user_id = @userId AND word = @word",
            new { userId, word = word.Trim().ToLowerInvariant() });
        return affected > 0 ? Ok(new { favorited = false }) : NotFound();
    }

    [HttpGet("favorites/{word}/status")]
    public async Task<IActionResult> FavoriteStatus(string word)
    {
        if (string.IsNullOrWhiteSpace(word) || word.Length > 150)
            return BadRequest(new { error = "Invalid word" });
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        var exists = await conn.QuerySingleAsync<bool>(
            "SELECT EXISTS(SELECT 1 FROM user_favorites WHERE user_id = @userId AND word = @word)",
            new { userId, word = word.Trim().ToLowerInvariant() });
        return Ok(new { favorited = exists });
    }

    // ── History ──────────────────────────────────────────────────────────────

    [HttpGet("history")]
    public async Task<IActionResult> GetHistory()
    {
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        // Last 100 unique words, most recent first
        var sql = """
            SELECT DISTINCT ON (word) word,
                   wd.data->'script_variants'->>'nastaliq' as urdu,
                   wd.data->'learning'->>'difficulty' as difficulty,
                   wd.data->'learning'->>'emoji' as emoji,
                   uh.looked_up_at
            FROM user_history uh
            LEFT JOIN word_definitions wd ON wd.word_lower = lower(uh.word)
            WHERE uh.user_id = @userId
            ORDER BY word, looked_up_at DESC
            LIMIT 100
            """;
        var results = await conn.QueryAsync(sql, new { userId });
        // Re-sort by looked_up_at descending
        return Ok(results.OrderByDescending(r => r.looked_up_at));
    }

    [HttpDelete("history")]
    public async Task<IActionResult> ClearHistory()
    {
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        await conn.ExecuteAsync("DELETE FROM user_history WHERE user_id = @userId", new { userId });
        return NoContent();
    }

    // ── Me ───────────────────────────────────────────────────────────────────

    [HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var userId = CurrentUserId;
        if (!userId.HasValue) return Unauthorized();

        using var conn = Connection();
        var user = await conn.QuerySingleOrDefaultAsync(
            "SELECT id, username, email, tier, created_at FROM users WHERE id = @id",
            new { id = userId });
        if (user == null) return NotFound();
        return Ok(user);
    }
}
