using Microsoft.AspNetCore.Mvc;
using UrduMeaning.Api.Services;
using System.ComponentModel.DataAnnotations;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _auth;

    public AuthController(IAuthService auth)
    {
        _auth = auth;
    }

    public record RegisterRequest(
        [Required, MinLength(2), MaxLength(50)] string Username,
        [Required, EmailAddress] string Email,
        [Required, MinLength(8)] string Password);

    public record LoginRequest(
        [Required, EmailAddress] string Email,
        [Required] string Password);

    public record RefreshRequest([Required] string RefreshToken);

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest req)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var result = await _auth.RegisterAsync(req.Username, req.Email, req.Password);
        if (result == null)
            return Conflict(new { error = "Email or username already in use" });

        return Ok(result);
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest req)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var result = await _auth.LoginAsync(req.Email, req.Password);
        if (result == null)
            return Unauthorized(new { error = "Invalid email or password" });

        return Ok(result);
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh([FromBody] RefreshRequest req)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var result = await _auth.RefreshAsync(req.RefreshToken);
        if (result == null)
            return Unauthorized(new { error = "Invalid or expired refresh token" });

        return Ok(result);
    }

    [HttpPost("logout")]
    public async Task<IActionResult> Logout([FromBody] RefreshRequest req)
    {
        await _auth.RevokeRefreshTokenAsync(req.RefreshToken);
        return NoContent();
    }
}
