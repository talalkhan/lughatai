using UrduMeaning.Api.Data;
using UrduMeaning.Api.Services;

namespace UrduMeaning.Api.BackgroundJobs;

public class WordQueueProcessor : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly IConfiguration _config;
    private readonly ILogger<WordQueueProcessor> _logger;
    private readonly SemaphoreSlim _semaphore;
    private volatile bool _rateLimited = false;

    public WordQueueProcessor(IServiceProvider services, IConfiguration config, ILogger<WordQueueProcessor> logger)
    {
        _services  = services;
        _config    = config;
        _logger    = logger;
        // Concurrency is configurable: BatchProcessor:Concurrency in appsettings.
        // Default 10 — safe for gpt-4o-mini (high TPM/RPM limits).
        // Lower to 3 if switching back to Claude Haiku (tight per-minute quotas).
        var concurrency = config.GetValue<int>("BatchProcessor:Concurrency", 10);
        _semaphore = new SemaphoreSlim(concurrency);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_config.GetValue<bool>("BatchProcessor:Enabled"))
        {
            _logger.LogInformation("WordQueueProcessor disabled via config");
            return;
        }

        var concurrency = _config.GetValue<int>("BatchProcessor:Concurrency", 10);
        var batchSize   = _config.GetValue<int>("BatchProcessor:BatchSize", 20);
        _logger.LogInformation("WordQueueProcessor started (concurrency={C}, batchSize={B})", concurrency, batchSize);

        while (!stoppingToken.IsCancellationRequested)
        {
            // If any worker signalled a rate limit, pause the whole processor
            // for 60 s before fetching a new batch. This lets the API quota reset.
            if (_rateLimited)
            {
                _rateLimited = false;
                _logger.LogWarning("Rate limited — pausing processor for 60 s");
                await Task.Delay(60_000, stoppingToken);
                continue;
            }

            try
            {
                await ProcessBatchAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Unexpected error in WordQueueProcessor loop");
            }

            await Task.Delay(5000, stoppingToken);
        }
    }

    private async Task ProcessBatchAsync(CancellationToken ct)
    {
        using var scope = _services.CreateScope();
        var repo = scope.ServiceProvider.GetRequiredService<IWordRepository>();
        var ai = scope.ServiceProvider.GetRequiredService<IWordAIService>();

        // Batch size is configurable: BatchProcessor:BatchSize in appsettings.
        var batchSize = _config.GetValue<int>("BatchProcessor:BatchSize", 20);
        var batch = (await repo.GetPendingBatchAsync(batchSize)).ToList();
        if (batch.Count == 0) return;

        _logger.LogInformation("Processing {Count} words from queue", batch.Count);

        var tasks = batch.Select(item => ProcessWordAsync(repo, ai, item.Id, item.Word, item.Priority, ct));
        await Task.WhenAll(tasks);
    }

    private async Task ProcessWordAsync(IWordRepository repo, IWordAIService ai, int id, string word, int priority, CancellationToken ct)
    {
        await _semaphore.WaitAsync(ct);
        try
        {
            var stage = priority >= 3 ? WordGenerationStage.Core : WordGenerationStage.Enriched;

            // Priority 3 gets a lean core entry first; higher-priority words keep
            // the richer full schema so common vocabulary stays best-in-class.
            var data = await ai.GenerateWordAsync(word, usePremium: false, stage: stage);
            await repo.SaveWordAsync(word, data);
            await repo.SetQueueStatusAsync(id, "done");

            _logger.LogInformation(
                "Processed '{Word}' (batch model: {Model}, stage: {Stage})",
                word,
                _config["AI:BatchModel"] ?? "default",
                stage.ToMetaValue());
        }
        catch (AIServiceException ex) when (ex.Message.Contains("429"))
        {
            // Rate limit is a timing issue, not a content failure.
            // Reset to pending WITHOUT burning an attempt so the word stays healthy.
            // Signal the batch loop to pause 60 s before the next batch.
            _logger.LogWarning("Rate limited on word '{Word}', resetting to pending (no attempt burned)", word);
            await repo.ResetToPendingAsync(id, ex.Message);
            _rateLimited = true;
        }
        catch (AIServiceException ex) when (ex.Message.StartsWith("TRUNCATED:"))
        {
            // Response was cut off at max_tokens — not a content error, just needs more tokens.
            // Reset to pending without burning an attempt. With max_tokens=8192 this should be rare.
            _logger.LogWarning("Response truncated for word '{Word}', resetting to pending", word);
            await repo.ResetToPendingAsync(id, ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process word '{Word}'", word);
            // Store inner exception message too so we can diagnose root causes from the DB
            var msg = ex.InnerException != null
                ? $"{ex.Message} | Inner: {ex.InnerException.Message}"
                : ex.Message;
            await repo.IncrementQueueAttemptsAsync(id, msg);
        }
        finally
        {
            _semaphore.Release();
        }
    }
}
