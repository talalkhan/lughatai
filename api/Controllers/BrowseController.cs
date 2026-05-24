using Microsoft.AspNetCore.Mvc;
using UrduMeaning.Api.Data;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api")]
public class BrowseController : ControllerBase
{
    private static readonly HashSet<string> ValidDifficulties =
        new(StringComparer.OrdinalIgnoreCase) { "beginner", "intermediate", "advanced", "expert" };

    private static readonly HashSet<string> ValidCefr =
        new(StringComparer.OrdinalIgnoreCase) { "A1", "A2", "B1", "B2", "C1", "C2" };

    private static readonly HashSet<string> ValidContexts =
        new(StringComparer.OrdinalIgnoreCase) { "daily", "literature", "poetry", "business", "science", "religion", "technology", "academic", "legal", "medical" };

    private readonly IWordRepository _repo;

    public BrowseController(IWordRepository repo)
    {
        _repo = repo;
    }

    [HttpGet("browse")]
    public async Task<IActionResult> Browse(
        [FromQuery] string? context,
        [FromQuery] string? difficulty,
        [FromQuery] string? cefr,
        [FromQuery] int page = 1,
        [FromQuery] int limit = 20)
    {
        if (page < 1) page = 1;
        if (limit < 1 || limit > 50) limit = 20;

        if (difficulty != null && !ValidDifficulties.Contains(difficulty))
            return BadRequest(new { error = "Invalid difficulty. Allowed: beginner, intermediate, advanced, expert." });

        if (cefr != null && !ValidCefr.Contains(cefr))
            return BadRequest(new { error = "Invalid cefr. Allowed: A1, A2, B1, B2, C1, C2." });

        if (context != null && !ValidContexts.Contains(context))
            return BadRequest(new { error = "Invalid context." });

        var words = await _repo.BrowseAsync(context, difficulty, cefr, page, limit);
        var total = await _repo.BrowseTotalAsync(context, difficulty, cefr);

        return Ok(new { words, total, page, limit });
    }
}
