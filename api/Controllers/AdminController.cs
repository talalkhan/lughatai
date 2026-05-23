using Dapper;
using Microsoft.AspNetCore.Mvc;
using LughatAI.Api.Data;

namespace LughatAI.Api.Controllers;

[ApiController]
[Route("api/admin")]
public class AdminController : ControllerBase
{
    private readonly IWordRepository _repo;
    private readonly IConfiguration _config;

    public AdminController(IWordRepository repo, IConfiguration config)
    {
        _repo = repo;
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

        var priority = Math.Clamp(request.Priority ?? 2, 1, 5);
        await _repo.AddToQueueAsync(request.Words, priority);
        return Ok(new { added = request.Words.Length, priority });
    }

    [HttpPost("queue/retry-failed")]
    public async Task<IActionResult> RetryFailed()
    {
        if (!IsAuthorized()) return Unauthorized(new { error = "Invalid admin key" });
        await _repo.RetryFailedAsync();
        return Ok(new { message = "Failed words reset to pending" });
    }

    // ── Corrections (P4-011) ─────────────────────────────────────────────────

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
        // Update correction status to dismissed
        using var conn = new Npgsql.NpgsqlConnection(_config.GetConnectionString("Default"));
        await conn.ExecuteAsync(
            "UPDATE corrections SET status = 'dismissed' WHERE id = @id",
            new { id });
        return Ok();
    }

    // ── Poetry verification (P4-012) ─────────────────────────────────────────

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
        await _repo.MarkPoetryVerifiedAsync(word.Trim().ToLowerInvariant());
        return Ok(new { verified = true });
    }

    private bool IsAuthorized()
    {
        var expectedKey = _config["Admin:ApiKey"];
        Request.Headers.TryGetValue("X-Admin-Key", out var providedKey);
        return !string.IsNullOrEmpty(expectedKey) && expectedKey == providedKey.ToString();
    }
}

public record AddWordsRequest(string[] Words, int? Priority);
