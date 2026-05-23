using LughatAI.Api.Data;
using LughatAI.Api.Services;

namespace LughatAI.Api.BackgroundJobs;

public class WordQueueProcessor : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly IConfiguration _config;
    private readonly ILogger<WordQueueProcessor> _logger;
    private readonly SemaphoreSlim _semaphore = new(5);

    public WordQueueProcessor(IServiceProvider services, IConfiguration config, ILogger<WordQueueProcessor> logger)
    {
        _services = services;
        _config = config;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_config.GetValue<bool>("BatchProcessor:Enabled"))
        {
            _logger.LogInformation("WordQueueProcessor disabled via config");
            return;
        }

        _logger.LogInformation("WordQueueProcessor started");

        while (!stoppingToken.IsCancellationRequested)
        {
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

        var batch = (await repo.GetPendingBatchAsync(10)).ToList();
        if (batch.Count == 0) return;

        _logger.LogInformation("Processing {Count} words from queue", batch.Count);

        var tasks = batch.Select(item => ProcessWordAsync(repo, ai, item.Id, item.Word, ct));
        await Task.WhenAll(tasks);
    }

    private async Task ProcessWordAsync(IWordRepository repo, IWordAIService ai, int id, string word, CancellationToken ct)
    {
        await _semaphore.WaitAsync(ct);
        try
        {
            await repo.SetQueueStatusAsync(id, "processing");

            var data = await ai.GenerateWordAsync(word, usePremium: false);
            await repo.SaveWordAsync(word, data);
            await repo.SetQueueStatusAsync(id, "done");

            _logger.LogInformation("Processed word '{Word}'", word);
        }
        catch (AIServiceException ex) when (ex.Message.Contains("429"))
        {
            _logger.LogWarning("Rate limited on word '{Word}', will retry", word);
            await repo.IncrementQueueAttemptsAsync(id, ex.Message);
            // Exponential backoff is handled at the batch level via the 5s loop delay
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process word '{Word}'", word);
            await repo.IncrementQueueAttemptsAsync(id, ex.Message);
        }
        finally
        {
            _semaphore.Release();
        }
    }
}
