using System.Security.Claims;
using Dapper;
using Microsoft.AspNetCore.Mvc;
using Npgsql;

namespace LughatAI.Api.Controllers;

[ApiController]
[Route("api/push")]
public class PushController : ControllerBase
{
    private readonly IConfiguration _config;
    private readonly ILogger<PushController> _logger;

    public PushController(IConfiguration config, ILogger<PushController> logger)
    {
        _config = config;
        _logger = logger;
    }

    private NpgsqlConnection Connection() => new(_config.GetConnectionString("Default"));

    public record PushSubscriptionDto(
        string Endpoint,
        PushKeysDto Keys);

    public record PushKeysDto(string P256dh, string Auth);

    /// <summary>
    /// Store a Web Push subscription. Called by the client after permission granted.
    /// Works for both authenticated users and anonymous visitors.
    /// </summary>
    [HttpPost("subscribe")]
    public async Task<IActionResult> Subscribe([FromBody] PushSubscriptionDto dto)
    {
        int? userId = null;
        var idClaim = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (idClaim != null) userId = int.Parse(idClaim);

        try
        {
            using var conn = Connection();
            // Upsert by endpoint (endpoint is globally unique per browser+site)
            await conn.ExecuteAsync("""
                INSERT INTO push_subscriptions (endpoint, p256dh, auth, user_id)
                VALUES (@endpoint, @p256dh, @auth, @userId)
                ON CONFLICT (endpoint) DO UPDATE
                SET p256dh = @p256dh, auth = @auth, user_id = @userId, updated_at = now()
                """,
                new { endpoint = dto.Endpoint, p256dh = dto.Keys.P256dh, auth = dto.Keys.Auth, userId });

            return Ok(new { subscribed = true });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to store push subscription");
            return StatusCode(500, new { error = "Could not save subscription" });
        }
    }

    [HttpDelete("unsubscribe")]
    public async Task<IActionResult> Unsubscribe([FromBody] PushSubscriptionDto dto)
    {
        using var conn = Connection();
        await conn.ExecuteAsync(
            "DELETE FROM push_subscriptions WHERE endpoint = @endpoint",
            new { endpoint = dto.Endpoint });
        return NoContent();
    }
}
