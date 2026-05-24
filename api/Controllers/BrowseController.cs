using Microsoft.AspNetCore.Mvc;
using UrduMeaning.Api.Data;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api")]
public class BrowseController : ControllerBase
{
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

        var words = await _repo.BrowseAsync(context, difficulty, cefr, page, limit);
        var total = await _repo.BrowseTotalAsync(context, difficulty, cefr);

        return Ok(new { words, total, page, limit });
    }
}
