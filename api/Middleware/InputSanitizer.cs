using System.Text.RegularExpressions;

namespace LughatAI.Api.Middleware;

public class InputSanitizerMiddleware
{
    private readonly RequestDelegate _next;
    private static readonly Regex DangerousChars = new(@"[<>""&]|script|javascript|vbscript|onload|onerror", RegexOptions.IgnoreCase | RegexOptions.Compiled);

    public InputSanitizerMiddleware(RequestDelegate next)
    {
        _next = next;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Check path segments for injection attempts
        var path = context.Request.Path.Value ?? "";
        if (DangerousChars.IsMatch(path))
        {
            context.Response.StatusCode = 400;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid request" });
            return;
        }

        // Check query strings
        foreach (var param in context.Request.Query)
        {
            if (DangerousChars.IsMatch(param.Value.ToString()))
            {
                context.Response.StatusCode = 400;
                await context.Response.WriteAsJsonAsync(new { error = "Invalid request" });
                return;
            }
        }

        // Add security headers
        context.Response.Headers.Append("X-Content-Type-Options", "nosniff");
        context.Response.Headers.Append("X-Frame-Options", "DENY");
        context.Response.Headers.Append("Referrer-Policy", "strict-origin-when-cross-origin");

        await _next(context);
    }
}
