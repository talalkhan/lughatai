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
    private readonly Channel<string> _channel;
    private readonly ConcurrentDictionary<string, byte> _queuedWords;

    public WordEnrichmentProcessor(IServiceProvider services, ILogger<WordEnrichmentProcessor> logger)
    {
        _services = services;
        _logger = logger;
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
        using var scope = _services.CreateScope();
        var repo = scope.ServiceProvider.GetRequiredService<IWordRepository>();
        var ai = scope.ServiceProvider.GetRequiredService<IWordAIService>();
        var cache = scope.ServiceProvider.GetRequiredService<ICacheService>();

        var current = await repo.GetWordAsync(word);
        if (!NeedsEnrichment(current))
            return;

        var enriched = await ai.GenerateWordAsync(word, usePremium: true, stage: WordGenerationStage.Enriched);
        await repo.SaveWordAsync(word, enriched);
        await cache.SetWordAsync(word, enriched);
        _logger.LogInformation("Enriched core entry for '{Word}' after user lookup", word);
    }

    public static bool NeedsEnrichment(WordData? data) =>
        string.Equals(data?.Meta?.Stage, WordGenerationStage.Core.ToMetaValue(), StringComparison.OrdinalIgnoreCase);
}
