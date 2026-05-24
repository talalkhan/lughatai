using Microsoft.AspNetCore.Mvc;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Services;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api")]
public class SearchController : ControllerBase
{
    private readonly IWordRepository _repo;
    private readonly IWordAIService _ai;

    public SearchController(IWordRepository repo, IWordAIService ai)
    {
        _repo = repo;
        _ai = ai;
    }

    /// <summary>English prefix autocomplete search.</summary>
    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string? q, [FromQuery] int limit = 10)
    {
        if (string.IsNullOrWhiteSpace(q) || q.Length < 2)
            return Ok(Array.Empty<object>());

        if (limit > 20) limit = 20;

        var prefix = q.Trim().ToLowerInvariant();
        var results = await _repo.SearchAsync(prefix, limit);
        return Ok(results);
    }

    /// <summary>
    /// Roman Urdu search (P4-010).
    /// Searches the stored roman_urdu JSONB field first.
    /// If no results found, calls AI to interpret the query as Roman Urdu.
    /// </summary>
    [HttpGet("search/roman")]
    public async Task<IActionResult> SearchRoman([FromQuery] string? q, [FromQuery] int limit = 10)
    {
        if (string.IsNullOrWhiteSpace(q) || q.Length < 2)
            return Ok(Array.Empty<object>());

        if (limit > 20) limit = 20;

        var query = q.Trim().ToLowerInvariant();

        // Phase 1: string match against stored roman_urdu field
        var stored = await _repo.SearchByRomanUrduAsync(query, limit);
        if (stored.Any())
            return Ok(new { results = stored, source = "db" });

        // Phase 2: AI interprets Roman Urdu → returns the canonical English word
        try
        {
            var englishWord = await _ai.InterpretRomanUrduAsync(query);
            if (string.IsNullOrEmpty(englishWord))
                return Ok(new { results = Array.Empty<object>(), source = "none" });

            var aiResults = await _repo.SearchAsync(englishWord.ToLowerInvariant(), limit);
            return Ok(new { results = aiResults, source = "ai", interpreted_as = englishWord });
        }
        catch
        {
            return Ok(new { results = Array.Empty<object>(), source = "none" });
        }
    }
}
