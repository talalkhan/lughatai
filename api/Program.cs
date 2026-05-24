using System.Threading.RateLimiting;
using UrduMeaning.Api.BackgroundJobs;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Middleware;
using UrduMeaning.Api.Services;
using Microsoft.AspNetCore.RateLimiting;
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

    // Redis
    var redisConnection = builder.Configuration["Redis:Connection"] ?? "localhost:6379";
    builder.Services.AddSingleton<IConnectionMultiplexer>(sp =>
    {
        try
        {
            return ConnectionMultiplexer.Connect(redisConnection);
        }
        catch (Exception ex)
        {
            Log.Warning(ex, "Redis connection failed, cache will be unavailable");
            return ConnectionMultiplexer.Connect("localhost:6379,abortConnect=false");
        }
    });

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
                  .AllowAnyMethod());
    });

    // JWT Authentication
    builder.Services.AddAuthentication("Bearer")
        .AddJwtBearer(options =>
        {
            var jwtConfig = builder.Configuration.GetSection("Jwt");
            var secret = jwtConfig["Secret"] ?? throw new InvalidOperationException("JWT Secret not configured");
            var keyBytes = System.Text.Encoding.UTF8.GetBytes(secret);
            options.TokenValidationParameters = new Microsoft.IdentityModel.Tokens.TokenValidationParameters
            {
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = new Microsoft.IdentityModel.Tokens.SymmetricSecurityKey(keyBytes),
                ValidateIssuer = false,
                ValidateAudience = false,
                ClockSkew = TimeSpan.Zero
            };
        });
    builder.Services.AddAuthorization();

    // Rate limiting — 60 req/min per IP
    builder.Services.AddRateLimiter(options =>
    {
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

    // Exclude admin from rate limiting
    app.MapControllerRoute(
        name: "admin",
        pattern: "api/admin/{**slug}");

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
