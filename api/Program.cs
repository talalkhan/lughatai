using System.Threading.RateLimiting;
using UrduMeaning.Api.BackgroundJobs;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Middleware;
using UrduMeaning.Api.Services;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.EntityFrameworkCore;
using Serilog;
using StackExchange.Redis;

Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    // Serilog — console always; Datadog sink in non-Development environments
    builder.Host.UseSerilog((ctx, services, config) =>
    {
        config.ReadFrom.Configuration(ctx.Configuration)
              .WriteTo.Console();

        var ddApiKey = ctx.Configuration["Datadog:ApiKey"];
        if (!string.IsNullOrEmpty(ddApiKey) && !ctx.HostingEnvironment.IsDevelopment())
        {
            config.WriteTo.DatadogLogs(
                apiKey: ddApiKey,
                source: "csharp",
                service: ctx.Configuration["Datadog:ServiceName"] ?? "urdumeaning-api",
                host: Environment.MachineName,
                tags: new[] { $"env:{ctx.HostingEnvironment.EnvironmentName.ToLower()}", "version:1.0" });
        }
    });

    // Application Insights — auto-tracks requests, dependencies (Claude/OpenAI calls), exceptions
    builder.Services.AddApplicationInsightsTelemetry();

    // Controllers + Swagger
    builder.Services.AddControllers();
    builder.Services.AddEndpointsApiExplorer();
    builder.Services.AddSwaggerGen(c =>
    {
        c.SwaggerDoc("v1", new() { Title = "UrduMeaning API", Version = "v1" });
    });

    // EF Core (migrations only)
    builder.Services.AddDbContext<AppDbContext>(options =>
        options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));

    // Redis is optional. Production currently runs without it; cache calls become no-ops.
    var redisEnabled = builder.Configuration.GetValue<bool>("Redis:Enabled", false);
    var redisConnection = builder.Configuration["Redis:Connection"];
    if (redisEnabled && !string.IsNullOrWhiteSpace(redisConnection))
    {
        builder.Services.AddSingleton(sp =>
        {
            try
            {
                return new RedisConnectionProvider(ConnectionMultiplexer.Connect(redisConnection));
            }
            catch (Exception ex)
            {
                Log.Warning(ex, "Redis connection failed, cache will be unavailable");
                return new RedisConnectionProvider(null);
            }
        });
    }
    else
    {
        builder.Services.AddSingleton(_ => new RedisConnectionProvider(null));
    }

    // HTTP clients — 90s timeout prevents hung connections from stalling the batch processor
    builder.Services.AddHttpClient("claude",  c => c.Timeout = TimeSpan.FromSeconds(90));
    builder.Services.AddHttpClient("openai",  c => c.Timeout = TimeSpan.FromSeconds(90));
    builder.Services.AddHttpClient("speech",  c => c.Timeout = TimeSpan.FromSeconds(30));

    // Application services
    builder.Services.AddScoped<IWordRepository, WordRepository>();
    builder.Services.AddScoped<ICacheService, CacheService>();
    builder.Services.AddScoped<IWordAIService, AIService>();
    builder.Services.AddScoped<IWordNormalizer, WordNormalizer>();
    builder.Services.AddScoped<IWordService, WordService>();
    builder.Services.AddScoped<IAudioService, AudioService>();
    builder.Services.AddScoped<IAuthService, AuthService>();

    // Background job
    builder.Services.AddSingleton<WordEnrichmentProcessor>();
    builder.Services.AddSingleton<IWordEnrichmentQueue>(sp => sp.GetRequiredService<WordEnrichmentProcessor>());
    builder.Services.AddHostedService<WordQueueProcessor>();
    builder.Services.AddHostedService(sp => sp.GetRequiredService<WordEnrichmentProcessor>());

    // CORS
    var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
        ?? new[] { "http://localhost:3000" };
    builder.Services.AddCors(options =>
    {
        options.AddDefaultPolicy(policy =>
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials());
    });

    // JWT Authentication
    builder.Services.AddAuthentication("Bearer")
        .AddJwtBearer(options =>
        {
            var jwtConfig = builder.Configuration.GetSection("Jwt");
            var secret = jwtConfig["Secret"];
            if (string.IsNullOrWhiteSpace(secret))
                throw new InvalidOperationException("Jwt:Secret is not configured. Set via environment variable Jwt__Secret.");
            var keyBytes = System.Text.Encoding.UTF8.GetBytes(secret);
            var issuer = jwtConfig["Issuer"] ?? "UrduMeaning";
            var audience = jwtConfig["Audience"] ?? "UrduMeaning.Web";
            options.TokenValidationParameters = new Microsoft.IdentityModel.Tokens.TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(keyBytes),
                ValidateIssuer = true,
                ValidIssuer = issuer,
                ValidateAudience = true,
                ValidAudience = audience,
                ValidateLifetime = true,
                ClockSkew = TimeSpan.Zero
            };
        });
    builder.Services.AddAuthorization();

    // Rate limiting
    builder.Services.AddRateLimiter(options =>
    {
        // General: 60 req/min per IP
        options.AddPolicy("ip", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 60,
                    Window = TimeSpan.FromMinutes(1),
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit = 0
                }));

        // Flag/report endpoint: 5 per IP per hour — stops scripted flooding
        options.AddPolicy("flag", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 5,
                    Window = TimeSpan.FromHours(1),
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit = 0
                }));

        // Auth endpoints: lower ceiling than general API to slow password spraying.
        options.AddPolicy("auth", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 10,
                    Window = TimeSpan.FromMinutes(5),
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit = 0
                }));

        // AI-backed search fallback: tighter because every miss can spend external API credits.
        options.AddPolicy("ai-search", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 10,
                    Window = TimeSpan.FromMinutes(1),
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit = 0
                }));

        // Admin endpoints: static-key protected today, so keep a narrow request budget.
        options.AddPolicy("admin", context =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: context.Connection.RemoteIpAddress?.ToString() ?? "unknown",
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    PermitLimit = 20,
                    Window = TimeSpan.FromMinutes(5),
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit = 0
                }));

        options.RejectionStatusCode = 429;
        options.OnRejected = async (ctx, ct) =>
        {
            ctx.HttpContext.Response.Headers.RetryAfter = "60";
            await ctx.HttpContext.Response.WriteAsJsonAsync(
                new { error = "Too many requests. Please wait before trying again." }, ct);
        };
    });

    // Health check
    builder.Services.AddHealthChecks();

    var app = builder.Build();

    app.UseForwardedHeaders(new ForwardedHeadersOptions
    {
        ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
    });

    app.UseMiddleware<InputSanitizerMiddleware>();

    if (app.Environment.IsDevelopment())
    {
        app.UseSwagger();
        app.UseSwaggerUI();
    }

    app.UseHttpsRedirection();
    app.UseCors();
    app.UseRateLimiter();
    app.UseAuthentication();
    app.UseAuthorization();

    app.MapControllers().RequireRateLimiting("ip");
    app.MapHealthChecks("/health").AllowAnonymous();

    // Startup validation — catch misconfigured secrets before accepting traffic
    if (!app.Environment.IsDevelopment())
    {
        var adminKey = app.Configuration["Admin:ApiKey"] ?? "";
        if (string.IsNullOrWhiteSpace(adminKey))
            throw new InvalidOperationException("Admin:ApiKey is not configured. Set via environment variable Admin__ApiKey.");

        var corsOrigins = app.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>() ?? [];
        if (corsOrigins.Any(o => o.Contains("localhost", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("Cors:AllowedOrigins contains localhost in a non-Development environment. Set production origins via Cors__AllowedOrigins__0.");

        var allowedHosts = app.Configuration["AllowedHosts"] ?? "*";
        if (allowedHosts == "*")
            Log.Warning("AllowedHosts is '*' in production — set ASPNETCORE_AllowedHosts=urdumeaning.com;www.urdumeaning.com");
    }

    app.Run();
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application startup failed");
    throw;
}
finally
{
    Log.CloseAndFlush();
}
