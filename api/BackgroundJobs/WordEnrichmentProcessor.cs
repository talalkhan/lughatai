using System.Collections.Concurrent;
using System.Threading.Channels;
using UrduMeaning.Api.Data;
using UrduMeaning.Api.Models;
using UrduMeaning.Api.Services;

namespace UrduMeaning.Api.BackgroundJobs;

public interface IWordEnrichmentQueue
{
    bool TryEnqueue(string word);
}

public class WordEnrichmentProcessor : BackgroundService, IWordEnrichmentQueue
{
    private readonly IServiceProvider _services;
    private readonly ILogger<WordEnrichmentProcessor> _logger;
    private readonly IConfiguration _config;
    private readonly Channel<string> _channel;
    private readonly ConcurrentDictionary<string, byte> _queuedWords;

    // Rate limiter — prevents crawlers from draining AI credits.
    // Tracks enrichments in the current 1-hour rolling window.
    private int _enrichmentsThisHour = 0;
    private DateTime _windowStart = DateTime.UtcNow;

    public WordEnrichmentProcessor(IServiceProvider services, ILogger<WordEnrichmentProcessor> logger, IConfiguration config)
    {
        _services = services;
        _logger = logger;
        _config = config;
        _channel = Channel.CreateUnbounded<string>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = false
        });
        _queuedWords = new ConcurrentDictionary<string, byte>(StringComparer.OrdinalIgnoreCase);
    }

    public bool TryEnqueue(string word)
    {
        if (string.IsNullOrWhiteSpace(word))
            return false;

        var normalized = word.Trim().ToLowerInvariant();
        if (!_queuedWords.TryAdd(normalized, 0))
            return false;

        if (!_channel.Writer.TryWrite(normalized))
        {
            _queuedWords.TryRemove(normalized, out _);
            return false;
        }

        return true;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await foreach (var word in _channel.Reader.ReadAllAsync(stoppingToken))
        {
            try
            {
                await EnrichAsync(word, stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Background enrichment failed for word '{Word}'", word);
            }
            finally
            {
                _queuedWords.TryRemove(word, out _);
            }
        }
    }

    private async Task EnrichAsync(string word, CancellationToken ct)
    {
        // Rate limit: max N enrichments per hour to prevent crawlers draining AI credits.
        var maxPerHour = _config.GetValue<int>("Enrichment:MaxPerHour", 30);
        if (!TryConsumeRateLimit(maxPerHour))
        {
            _logger.LogDebug("Enrichment rate limit reached ({Max}/hr) — skipping '{Word}'", maxPerHour, word);
            return;
        }

        using var scope = _services.CreateScope();
        var repo = scope.ServiceProvider.GetRequiredService<IWordRepository>();
        var ai = scope.ServiceProvider.GetRequiredService<IWordAIService>();
        var cache = scope.ServiceProvider.GetRequiredService<ICacheService>();

        var current = await repo.GetWordAsync(word);
        if (!NeedsEnrichment(current))
            return;

        var enriched = await ai.GenerateWordAsync(word, usePremium: false, stage: WordGenerationStage.Enriched);
        await repo.SaveWordAsync(word, enriched);
        await cache.SetWordAsync(word, enriched);
        _logger.LogInformation("Enriched core entry for '{Word}' after user lookup", word);
    }

    private bool TryConsumeRateLimit(int maxPerHour)
    {
        lock (this)
        {
            var now = DateTime.UtcNow;
            if ((now - _windowStart).TotalHours >= 1.0)
            {
                _windowStart = now;
                _enrichmentsThisHour = 0;
            }

            if (_enrichmentsThisHour >= maxPerHour)
                return false;

            _enrichmentsThisHour++;
            return true;
        }
    }

    public static bool NeedsEnrichment(WordData? data) =>
        string.Equals(data?.Meta?.Stage, WordGenerationStage.Core.ToMetaValue(), StringComparison.OrdinalIgnoreCase);
}
