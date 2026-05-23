using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using Dapper;
using LughatAI.Api.Models;
using Microsoft.IdentityModel.Tokens;
using Npgsql;

namespace LughatAI.Api.Services;

public interface IAuthService
{
    Task<AuthResult?> RegisterAsync(string username, string email, string password);
    Task<AuthResult?> LoginAsync(string email, string password);
    Task<AuthResult?> RefreshAsync(string refreshToken);
    Task RevokeRefreshTokenAsync(string refreshToken);
    int? GetUserIdFromToken(string token);
}

public record AuthResult(string AccessToken, string RefreshToken, UserDto User);
public record UserDto(int Id, string Username, string Email, string Tier);

public class AuthService : IAuthService
{
    private readonly IConfiguration _config;
    private readonly ILogger<AuthService> _logger;

    public AuthService(IConfiguration config, ILogger<AuthService> logger)
    {
        _config = config;
        _logger = logger;
    }

    private NpgsqlConnection Connection() =>
        new(_config.GetConnectionString("Default"));

    public async Task<AuthResult?> RegisterAsync(string username, string email, string password)
    {
        var hash = BCrypt.Net.BCrypt.HashPassword(password);
        using var conn = Connection();
        try
        {
            var sql = """
                INSERT INTO users (username, email, password_hash)
                VALUES (@username, @email, @hash)
                RETURNING id, username, email, tier
                """;
            var user = await conn.QuerySingleAsync<(int Id, string Username, string Email, string Tier)>(
                sql, new { username, email, hash });
            return await IssueTokensAsync(conn, user.Id, user.Username, user.Email, user.Tier);
        }
        catch (PostgresException ex) when (ex.SqlState == "23505") // unique violation
        {
            _logger.LogWarning("Registration failed: duplicate email or username '{Email}'", email);
            return null;
        }
    }

    public async Task<AuthResult?> LoginAsync(string email, string password)
    {
        using var conn = Connection();
        var sql = "SELECT id, username, email, password_hash, tier FROM users WHERE email = @email LIMIT 1";
        var row = await conn.QuerySingleOrDefaultAsync<(int Id, string Username, string Email, string Hash, string Tier)?>(
            sql, new { email });

        if (row == null) return null;
        if (!BCrypt.Net.BCrypt.Verify(password, row.Value.Hash)) return null;

        return await IssueTokensAsync(conn, row.Value.Id, row.Value.Username, row.Value.Email, row.Value.Tier);
    }

    public async Task<AuthResult?> RefreshAsync(string refreshToken)
    {
        using var conn = Connection();
        var sql = """
            SELECT id, username, email, tier
            FROM users
            WHERE refresh_token = @refreshToken
              AND refresh_token_expires_at > now()
            LIMIT 1
            """;
        var row = await conn.QuerySingleOrDefaultAsync<(int Id, string Username, string Email, string Tier)?>(
            sql, new { refreshToken });

        if (row == null) return null;
        return await IssueTokensAsync(conn, row.Value.Id, row.Value.Username, row.Value.Email, row.Value.Tier);
    }

    public async Task RevokeRefreshTokenAsync(string refreshToken)
    {
        using var conn = Connection();
        await conn.ExecuteAsync(
            "UPDATE users SET refresh_token = NULL, refresh_token_expires_at = NULL WHERE refresh_token = @refreshToken",
            new { refreshToken });
    }

    public int? GetUserIdFromToken(string token)
    {
        try
        {
            var key = System.Text.Encoding.UTF8.GetBytes(_config["Jwt:Secret"]!);
            var handler = new JwtSecurityTokenHandler();
            var principal = handler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new SymmetricSecurityKey(key),
                ValidateIssuer = false,
                ValidateAudience = false,
                ClockSkew = TimeSpan.Zero
            }, out _);
            var claim = principal.FindFirst(ClaimTypes.NameIdentifier)?.Value;
            return claim == null ? null : int.Parse(claim);
        }
        catch
        {
            return null;
        }
    }

    private async Task<AuthResult> IssueTokensAsync(
        NpgsqlConnection conn, int userId, string username, string email, string tier)
    {
        var accessToken = GenerateJwt(userId, username, email);
        var refreshToken = GenerateRefreshToken();
        var refreshExpiry = DateTime.UtcNow.AddDays(
            _config.GetValue<int>("Jwt:RefreshExpiryDays", 30));

        await conn.ExecuteAsync(
            "UPDATE users SET refresh_token = @refreshToken, refresh_token_expires_at = @refreshExpiry, updated_at = now() WHERE id = @userId",
            new { refreshToken, refreshExpiry, userId });

        return new AuthResult(accessToken, refreshToken, new UserDto(userId, username, email, tier));
    }

    private string GenerateJwt(int userId, string username, string email)
    {
        var key = new SymmetricSecurityKey(System.Text.Encoding.UTF8.GetBytes(_config["Jwt:Secret"]!));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var expiryHours = _config.GetValue<int>("Jwt:ExpiryHours", 1);

        var token = new JwtSecurityToken(
            claims: new[]
            {
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Name, username),
                new Claim(ClaimTypes.Email, email),
            },
            expires: DateTime.UtcNow.AddHours(expiryHours),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static string GenerateRefreshToken()
    {
        var bytes = new byte[64];
        RandomNumberGenerator.Fill(bytes);
        return Convert.ToBase64String(bytes);
    }
}
