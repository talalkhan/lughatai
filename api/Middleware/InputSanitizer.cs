using System.Text.RegularExpressions;

namespace UrduMeaning.Api.Middleware;

public class InputSanitizerMiddleware
{
    private readonly RequestDelegate _next;

    // Matches actual injection patterns only — not innocent characters like & " < >
    // or words that happen to contain "script" (e.g. "manuscript", "subscription").
    private static readonly Regex AttackPattern = new(
        @"<\s*script|javascript\s*:|vbscript\s*:|on\w+\s*=|eval\s*\(|expression\s*\(|document\.|window\.",
        RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public InputSanitizerMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? "";
        if (AttackPattern.IsMatch(path))
        {
            context.Response.StatusCode = 400;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid request" });
            return;
        }

        foreach (var param in context.Request.Query)
        {
            if (AttackPattern.IsMatch(param.Value.ToString()))
            {
                context.Response.StatusCode = 400;
                await context.Response.WriteAsJsonAsync(new { error = "Invalid request" });
                return;
            }
        }

        context.Response.Headers.Append("X-Content-Type-Options", "nosniff");
        context.Response.Headers.Append("X-Frame-Options", "DENY");
        context.Response.Headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");
        context.Response.Headers.Append("Content-Security-Policy", "default-src 'none'");
        context.Response.Headers.Append("Permissions-Policy", "geolocation=(), microphone=(), camera=()");

        if (context.Request.IsHttps)
            context.Response.Headers.Append("Strict-Transport-Security", "max-age=31536000; includeSubDomains");

        await _next(context);
    }
}
