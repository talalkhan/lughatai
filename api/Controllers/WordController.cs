using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Services;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api")]
public class WordController : ControllerBase
{
    private readonly IWordService _wordService;
    private readonly IAudioService _audioService;
    private readonly IWordRepository _repo;
    private readonly IConfiguration _config;

    public WordController(IWordService wordService, IAudioService audioService, IWordRepository repo, IConfiguration config)
    {
        _wordService = wordService;
        _audioService = audioService;
        _repo = repo;
        _config = config;
    }

    [HttpGet("word/{word}")]
    public async Task<IActionResult> GetWord(string word)
    {
        if (string.IsNullOrWhiteSpace(word) || word.Length > 150)
            return BadRequest(new { error = "Invalid word" });

        int? userId = null;
        var idClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (idClaim != null) userId = int.Parse(idClaim);

        var result = await _wordService.GetWordAsync(word, userId);
        if (result == null)
        {
            // Two distinct cases:
            // 1. WordGeneration disabled → word simply not in dictionary → 404
            // 2. WordGeneration enabled but AI failed → service error → 503
            var generationEnabled = _config.GetValue<bool>("WordGeneration:Enabled", false);
            if (!generationEnabled)
                return NotFound(new { error = "Word not found" });
            return StatusCode(503, new { error = "Service temporarily unavailable" });
        }

        return Ok(result);
    }

    [HttpGet("word/random")]
    public async Task<IActionResult> GetRandom([FromQuery] string? difficulty)
    {
        var result = await _wordService.GetRandomWordAsync(difficulty);
        if (result == null)
            return NotFound(new { error = "No words available" });

        return Ok(result);
    }

    [HttpGet("word-of-the-day")]
    public async Task<IActionResult> GetWordOfTheDay()
    {
        var result = await _wordService.GetWordOfTheDayAsync();
        if (result == null)
            return NotFound(new { error = "No word of the day available" });

        return Ok(result);
    }

    /// <summary>
    /// Returns a redirect to the audio MP3 for the word in the requested language.
    /// Generates and caches audio on first request (lazy TTS).
    /// </summary>
    [HttpGet("word/{word}/audio")]
    public async Task<IActionResult> GetAudio(string word, [FromQuery] string lang = "en")
    {
        if (lang != "en" && lang != "ur")
            return BadRequest(new { error = "lang must be 'en' or 'ur'" });

        if (string.IsNullOrWhiteSpace(word) || word.Length > 150)
            return BadRequest(new { error = "Invalid word" });

        var data = await _wordService.GetWordAsync(word);
        if (data == null)
            return NotFound(new { error = "Word not found" });

        var url = await _audioService.GetOrGenerateAsync(word, data, lang);
        if (url == null)
            return StatusCode(503, new { error = "Audio generation temporarily unavailable" });

        return Redirect(url);
    }

    /// <summary>Flag a word entry as having an error (P4-011). Auth optional — anonymous allowed.</summary>
    public record FlagRequest(string Reason, string? Notes);

    [HttpPost("word/{word}/flag")]
    [Microsoft.AspNetCore.RateLimiting.EnableRateLimiting("flag")]
    public async Task<IActionResult> FlagWord(string word, [FromBody] FlagRequest req)
    {
        var allowed = new[] { "translation", "example", "poetry", "other" };
        if (!allowed.Contains(req.Reason)) return BadRequest(new { error = "Invalid reason" });
        if (string.IsNullOrWhiteSpace(word) || word.Length > 150) return BadRequest(new { error = "Invalid word" });
        if (req.Notes?.Length > 500) return BadRequest(new { error = "Notes must be 500 characters or fewer" });

        int? userId = null;
        var idClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (idClaim != null) userId = int.Parse(idClaim);

        await _repo.AddCorrectionAsync(word, userId, req.Reason, req.Notes);
        return Ok(new { flagged = true });
    }
}
