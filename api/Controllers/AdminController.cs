using Dapper;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Services;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api/admin")]
[EnableRateLimiting("admin")]
public class AdminController : ControllerBase
{
    private const int MaxQueueAddWords = 1000;
    private const int MaxWordLength = 64;
    private static readonly Regex AdminWordPattern = new(@"^[a-z]+$", RegexOptions.Compiled);
    private readonly IWordRepository _repo;
    private readonly ICacheService _cache;
    private readonly IConfiguration _config;

    public AdminController(IWordRepository repo, ICacheService cache, IConfiguration config)
    {
        _repo = repo;
        _cache = cache;
        _config = config;
    }

    [HttpGet("queue/status")]
    public async Task<IActionResult> GetQueueStatus()
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        var status = await _repo.GetQueueStatusAsync();
        return Ok(status);
    }

    [HttpPost("queue/add")]
    public async Task<IActionResult> AddToQueue([FromBody] AddWordsRequest request)
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        if (request.Words == null || request.Words.Length == 0)
            return BadRequest(new { error = "Words array is required" });

        if (request.Words.Length > MaxQueueAddWords)
            return BadRequest(new { error = $"At most {MaxQueueAddWords} words can be added at once" });

        var cleanedWords = request.Words
            .Select(w => w.Trim().ToLowerInvariant())
            .Where(w => !string.IsNullOrWhiteSpace(w))
            .Distinct()
            .ToArray();

        var invalid = cleanedWords
            .FirstOrDefault(w => w.Length > MaxWordLength || !AdminWordPattern.IsMatch(w));
        if (invalid != null)
            return BadRequest(new { error = $"Invalid word '{invalid}'. Use single lowercase English alphabetic tokens only." });

        var priority = Math.Clamp(request.Priority ?? 2, 1, 5);
        await _repo.AddToQueueAsync(cleanedWords, priority);
        return Ok(new { added = cleanedWords.Length, priority });
    }

    [HttpPost("queue/retry-failed")]
    public async Task<IActionResult> RetryFailed()
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        await _repo.RetryFailedAsync();
        return Ok(new { message = "Failed words reset to pending" });
    }

    // ── Corrections ──────────────────────────────────────────────────────────

    [HttpGet("corrections")]
    public async Task<IActionResult> GetCorrections()
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        var corrections = await _repo.GetOpenCorrectionsAsync();
        return Ok(corrections);
    }

    [HttpPost("corrections/{id}/dismiss")]
    public async Task<IActionResult> DismissCorrection(int id)
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        using var conn = new Npgsql.NpgsqlConnection(_config.GetConnectionString("Default"));
        await conn.ExecuteAsync(
            "UPDATE corrections SET status = 'dismissed' WHERE id = @id",
            new { id });
        return Ok();
    }

    // ── Poetry verification ───────────────────────────────────────────────────

    [HttpGet("poetry/unverified")]
    public async Task<IActionResult> GetUnverifiedPoetry()
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        var items = await _repo.GetUnverifiedPoetryAsync();
        return Ok(items);
    }

    [HttpPost("poetry/{word}/verify")]
    public async Task<IActionResult> VerifyPoetry(string word)
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        var normalized = word.Trim().ToLowerInvariant();
        await _repo.MarkPoetryVerifiedAsync(normalized);
        await _cache.InvalidateWordAsync(normalized);
        return Ok(new { verified = true });
    }

    private bool IsAuthorized()
    {
        var expectedKey = _config["Admin:ApiKey"];
        Request.Headers.TryGetValue("X-Admin-Key", out var providedKey);
        if (string.IsNullOrEmpty(expectedKey))
            return false;

        var provided = providedKey.ToString();
        if (string.IsNullOrEmpty(provided))
            return false;

        var expectedBytes = Encoding.UTF8.GetBytes(expectedKey);
        var providedBytes = Encoding.UTF8.GetBytes(provided);
        return expectedBytes.Length == providedBytes.Length
            && CryptographicOperations.FixedTimeEquals(expectedBytes, providedBytes);
    }
}

public record AddWordsRequest(string[] Words, int? Priority);
