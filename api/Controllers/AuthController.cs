using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using UrduMeaning.Api.Services;
using System.ComponentModel.DataAnnotations;

namespace UrduMeaning.Api.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _auth;
    private readonly IWebHostEnvironment _env;
    private string RefreshCookieName => _env.IsDevelopment()
        ? "urdumeaning_refresh"
        : "__Host-urdumeaning_refresh";

    public AuthController(IAuthService auth, IWebHostEnvironment env)
    {
        _auth = auth;
        _env = env;
    }

    public record RegisterRequest(
        [Required, MinLength(2), MaxLength(50)] string Username,
        [Required, EmailAddress] string Email,
        [Required, MinLength(8)] string Password);

    public record LoginRequest(
        [Required, EmailAddress] string Email,
        [Required] string Password);

    public record RefreshRequest(string? RefreshToken);

    [HttpPost("register")]
    [EnableRateLimiting("auth")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest req)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var result = await _auth.RegisterAsync(req.Username, req.Email, req.Password);
        if (result == null)
            return Conflict(new { error = "Email or username already in use" });

        return Ok(AttachRefreshCookie(result));
    }

    [HttpPost("login")]
    [EnableRateLimiting("auth")]
    public async Task<IActionResult> Login([FromBody] LoginRequest req)
    {
        if (!ModelState.IsValid) return BadRequest(ModelState);

        var result = await _auth.LoginAsync(req.Email, req.Password);
        if (result == null)
            return Unauthorized(new { error = "Invalid email or password" });

        return Ok(AttachRefreshCookie(result));
    }

    [HttpPost("refresh")]
    [EnableRateLimiting("auth")]
    public async Task<IActionResult> Refresh([FromBody] RefreshRequest req)
    {
        var token = GetRefreshToken(req.RefreshToken);
        if (string.IsNullOrWhiteSpace(token))
            return BadRequest(new { error = "Refresh token is required" });

        var result = await _auth.RefreshAsync(token);
        if (result == null)
            return Unauthorized(new { error = "Invalid or expired refresh token" });

        return Ok(AttachRefreshCookie(result));
    }

    [HttpPost("logout")]
    [EnableRateLimiting("auth")]
    public async Task<IActionResult> Logout([FromBody] RefreshRequest req)
    {
        var token = GetRefreshToken(req.RefreshToken);
        if (!string.IsNullOrWhiteSpace(token))
            await _auth.RevokeRefreshTokenAsync(token);
        Response.Cookies.Delete(RefreshCookieName, CookieOptions());
        return NoContent();
    }

    private AuthResult AttachRefreshCookie(AuthResult result)
    {
        if (!string.IsNullOrWhiteSpace(result.RefreshToken))
            Response.Cookies.Append(RefreshCookieName, result.RefreshToken, CookieOptions());

        return result with { RefreshToken = null };
    }

    private string? GetRefreshToken(string? bodyToken)
    {
        if (!string.IsNullOrWhiteSpace(bodyToken))
            return bodyToken;

        return Request.Cookies.TryGetValue(RefreshCookieName, out var cookieToken)
            ? cookieToken
            : null;
    }

    private CookieOptions CookieOptions() => new()
    {
        HttpOnly = true,
        Secure = !_env.IsDevelopment(),
        SameSite = _env.IsDevelopment() ? SameSiteMode.Lax : SameSiteMode.None,
        Path = "/",
        MaxAge = TimeSpan.FromDays(30)
    };
}
