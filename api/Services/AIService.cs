using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using UrduMeaning.Api.Models;

namespace UrduMeaning.Api.Services;

public class AIServiceException : Exception
{
    public AIServiceException(string message, Exception? inner = null) : base(message, inner) { }
}

public interface IWordAIService
{
    Task<WordData> GenerateWordAsync(string word, bool usePremium = false, WordGenerationStage stage = WordGenerationStage.Enriched);
    /// <summary>
    /// Given a Roman Urdu query (e.g. "sukoon"), returns the English word it corresponds to.
    /// Returns null if the AI cannot interpret it.
    /// </summary>
    Task<string?> InterpretRomanUrduAsync(string romanUrdu);
}

public class AIService : IWordAIService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _config;
    private readonly ILogger<AIService> _logger;
    private readonly string _systemPrompt;
    private readonly string _corePromptAddendum;
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        PropertyNameCaseInsensitive = true
    };

    public AIService(IHttpClientFactory httpClientFactory, IConfiguration config, ILogger<AIService> logger)
    {
        _httpClientFactory = httpClientFactory;
        _config = config;
        _logger = logger;

        var promptPath = Path.Combine(AppContext.BaseDirectory, "Prompts", "ai_system_prompt.txt");
        _systemPrompt = File.ReadAllText(promptPath);
        var corePromptPath = Path.Combine(AppContext.BaseDirectory, "Prompts", "ai_core_prompt_addendum.txt");
        _corePromptAddendum = File.Exists(corePromptPath) ? File.ReadAllText(corePromptPath) : string.Empty;
    }

    public async Task<WordData> GenerateWordAsync(string word, bool usePremium = false, WordGenerationStage stage = WordGenerationStage.Enriched)
    {
        var model = usePremium
            ? _config["AI:LiveModel"] ?? "claude-sonnet-4-6"
            : _config["AI:BatchModel"] ?? "claude-haiku-4-5-20251001";
        var prompt = BuildPrompt(stage);

        // If the configured batch model is an OpenAI model (gpt-*), route directly
        // to OpenAI — no Claude attempt, no fallback dance.
        if (model.StartsWith("gpt-", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var result = await CallOpenAIAsync(word, prompt, model);
                return StampMeta(result, model, "openai", stage);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "OpenAI failed for word '{Word}'", word);
                throw new AIServiceException($"OpenAI failed for word '{word}'", ex);
            }
        }

        // Claude path
        try
        {
            var result = await CallClaudeAsync(word, prompt, model);
            return StampMeta(result, model, "claude", stage);
        }
        catch (AIServiceException ex) when (ex.Message.StartsWith("429:"))
        {
            // Rate limit — don't fall back to OpenAI, just re-throw so the batch
            // processor can back off and requeue.
            _logger.LogWarning("Rate limited by Claude API for '{Word}', requeueing", word);
            throw;
        }
        catch (Exception claudeEx)
        {
            var openAiKey = _config["AI:OpenAIApiKey"];
            var openAiConfigured = !string.IsNullOrWhiteSpace(openAiKey)
                                   && openAiKey != "YOUR_KEY";

            if (!openAiConfigured)
            {
                _logger.LogError(claudeEx, "Claude failed for word '{Word}' (no OpenAI fallback configured)", word);
                throw new AIServiceException($"Claude failed for word '{word}'", claudeEx);
            }

            _logger.LogError(claudeEx, "Claude failed for word '{Word}', attempting OpenAI fallback", word);
            try
            {
                var result = await CallOpenAIAsync(word, prompt, "gpt-4o-mini");
                return StampMeta(result, "gpt-4o-mini", "openai", stage);
            }
            catch (Exception openAiEx)
            {
                _logger.LogError(openAiEx, "OpenAI fallback also failed for word '{Word}'", word);
                throw new AIServiceException($"All AI providers failed for word '{word}'", openAiEx);
            }
        }
    }

    private async Task<WordData> CallClaudeAsync(string word, string prompt, string model)
    {
        var apiKey = _config["AI:AnthropicApiKey"]
            ?? throw new AIServiceException("Anthropic API key not configured");
        var userPrompt = BuildWordRequest(word);

        var payload = new
        {
            model,
            max_tokens = 8192,   // 8192 for rich Urdu content — common words like "good"/"time" fill 4096+
            system = prompt,
            messages = new[] { new { role = "user", content = userPrompt } }
        };

        for (int attempt = 0; attempt < 2; attempt++)
        {
            var client = _httpClientFactory.CreateClient("claude");
            client.DefaultRequestHeaders.Clear();
            client.DefaultRequestHeaders.Add("x-api-key", apiKey);
            client.DefaultRequestHeaders.Add("anthropic-version", "2023-06-01");

            var json = JsonSerializer.Serialize(payload);
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };

            using var response = await client.SendAsync(request);

            // Rate limited — throw a recognisable message so callers can requeue
            // without triggering the OpenAI fallback
            if ((int)response.StatusCode == 429)
            {
                var retryAfter = response.Headers.RetryAfter?.Delta?.TotalSeconds;
                var body429 = await response.Content.ReadAsStringAsync();
                _logger.LogWarning("429 rate limit for '{Word}'. RetryAfter={RetryAfter}s. Body={Body}",
                    word, retryAfter, body429[..Math.Min(300, body429.Length)]);
                throw new AIServiceException($"429: Claude rate limited for '{word}'");
            }

            // Overloaded — retry once after a short delay
            if ((int)response.StatusCode == 529 && attempt == 0)
            {
                await Task.Delay(2000);
                continue;
            }

            response.EnsureSuccessStatusCode();

            var body = await response.Content.ReadAsStringAsync();
            var parsed = JsonNode.Parse(body);
            var text = parsed?["content"]?[0]?["text"]?.GetValue<string>()
                ?? throw new AIServiceException("Claude returned empty response");

            // If the model ran out of tokens the JSON is truncated and will fail to parse.
            // Throw a recognisable exception so the caller can reset without burning an attempt.
            var stopReason = parsed?["stop_reason"]?.GetValue<string>();
            if (stopReason == "max_tokens")
            {
                _logger.LogWarning("Response truncated at max_tokens for word '{Word}' — consider a shorter prompt", word);
                throw new AIServiceException($"TRUNCATED: max_tokens exceeded for '{word}'");
            }

            return ParseWordData(text, word);
        }

        throw new AIServiceException("Claude returned 529 after retry");
    }

    private async Task<WordData> CallOpenAIAsync(string word, string prompt, string model = "gpt-4o-mini")
    {
        var apiKey = _config["AI:OpenAIApiKey"]
            ?? throw new AIServiceException("OpenAI API key not configured");
        var userPrompt = BuildWordRequest(word);

        var payload = new
        {
            model,
            max_tokens = 8192,   // match Claude budget; GPT-4o-mini supports up to 16384
            messages = new[]
            {
                new { role = "system", content = prompt },
                new { role = "user", content = userPrompt }
            }
        };

        var client = _httpClientFactory.CreateClient("openai");
        client.DefaultRequestHeaders.Clear();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

        var json = JsonSerializer.Serialize(payload);
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions")
        {
            Content = new StringContent(json, Encoding.UTF8, "application/json")
        };

        using var response = await client.SendAsync(request);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        var parsed = JsonNode.Parse(body);
        var text = parsed?["choices"]?[0]?["message"]?["content"]?.GetValue<string>()
            ?? throw new AIServiceException("OpenAI returned empty response");

        var finishReason = parsed?["choices"]?[0]?["finish_reason"]?.GetValue<string>();
        if (finishReason == "length")
        {
            _logger.LogWarning("OpenAI response truncated at max_tokens for word '{Word}'", word);
            throw new AIServiceException($"TRUNCATED: max_tokens exceeded for '{word}'");
        }

        return ParseWordData(text, word);
    }

    private string BuildPrompt(WordGenerationStage stage)
    {
        if (stage != WordGenerationStage.Core || string.IsNullOrWhiteSpace(_corePromptAddendum))
            return _systemPrompt;

        return $"{_systemPrompt}{Environment.NewLine}{Environment.NewLine}{_corePromptAddendum}";
    }

    private static string BuildWordRequest(string word)
    {
        return $"English headword: {word}{Environment.NewLine}Use this exact headword in the top-level \"word\" field. Do not autocorrect, normalize, or substitute a different word.";
    }

    private static WordData StampMeta(WordData data, string model, string generatedBy, WordGenerationStage stage)
    {
        if (stage == WordGenerationStage.Core)
            ApplyCoreShape(data);

        data.Meta ??= new MetaInfo();
        data.Meta.GeneratedBy = generatedBy;
        data.Meta.GeneratedAt = DateTime.UtcNow.ToString("O");
        data.Meta.Model = model;
        data.Meta.Stage = stage.ToMetaValue();
        data.Meta.Version ??= "1.0";
        return data;
    }

    private static void ApplyCoreShape(WordData data)
    {
        data.Etymology = null;
        data.WordFamily = new();
        data.RelatedWords = new RelatedWords
        {
            SeeAlso = new(),
            ThematicGroup = new()
        };
        data.MemoryTip = null;
        data.UrduPoetry = null;
        data.UrduProverb = null;
        data.IslamicReference = null;
    }

    public async Task<string?> InterpretRomanUrduAsync(string romanUrdu)
    {
        var model = _config["AI:BatchModel"] ?? "claude-haiku-4-5-20251001";
        if (model.StartsWith("gpt-", StringComparison.OrdinalIgnoreCase))
            return await InterpretRomanUrduWithOpenAIAsync(romanUrdu, model);

        var apiKey = _config["AI:AnthropicApiKey"];
        if (string.IsNullOrEmpty(apiKey)) return null;

        var payload = new
        {
            model,
            max_tokens = 50,
            system = "You are a Roman Urdu to English translator. The user will give you a word or phrase written in Roman Urdu (Urdu transliterated into Latin script). Reply with ONLY the single best English translation word. No explanation, no punctuation, just the word.",
            messages = new[] { new { role = "user", content = romanUrdu } }
        };

        try
        {
            var client = _httpClientFactory.CreateClient("claude");
            client.DefaultRequestHeaders.Clear();
            client.DefaultRequestHeaders.Add("x-api-key", apiKey);
            client.DefaultRequestHeaders.Add("anthropic-version", "2023-06-01");

            var json = JsonSerializer.Serialize(payload);
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.anthropic.com/v1/messages")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            using var response = await client.SendAsync(request);
            if (!response.IsSuccessStatusCode) return null;

            var body = await response.Content.ReadAsStringAsync();
            var parsed = JsonNode.Parse(body);
            var word = parsed?["content"]?[0]?["text"]?.GetValue<string>()?.Trim().ToLowerInvariant();
            return string.IsNullOrWhiteSpace(word) ? null : word;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Roman Urdu interpretation failed for '{Query}'", romanUrdu);
            return null;
        }
    }

    private async Task<string?> InterpretRomanUrduWithOpenAIAsync(string romanUrdu, string model)
    {
        var apiKey = _config["AI:OpenAIApiKey"];
        if (string.IsNullOrWhiteSpace(apiKey) || apiKey == "YOUR_KEY")
            return null;

        var payload = new
        {
            model,
            max_tokens = 50,
            messages = new[]
            {
                new
                {
                    role = "system",
                    content = "You are a Roman Urdu to English translator. The user will give you a word or phrase written in Roman Urdu (Urdu transliterated into Latin script). Reply with ONLY the single best English translation word. No explanation, no punctuation, just the word."
                },
                new { role = "user", content = romanUrdu }
            }
        };

        try
        {
            var client = _httpClientFactory.CreateClient("openai");
            client.DefaultRequestHeaders.Clear();
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);

            var json = JsonSerializer.Serialize(payload);
            using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions")
            {
                Content = new StringContent(json, Encoding.UTF8, "application/json")
            };
            using var response = await client.SendAsync(request);
            if (!response.IsSuccessStatusCode) return null;

            var body = await response.Content.ReadAsStringAsync();
            var parsed = JsonNode.Parse(body);
            var word = parsed?["choices"]?[0]?["message"]?["content"]?.GetValue<string>()?.Trim().ToLowerInvariant();
            return string.IsNullOrWhiteSpace(word) ? null : word;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Roman Urdu interpretation via OpenAI failed for '{Query}'", romanUrdu);
            return null;
        }
    }

    private WordData ParseWordData(string text, string word)
    {
        // Extract the JSON object by finding the first { and last }.
        // This handles any wrapping Claude adds: markdown fences, preamble
        // text, trailing commentary — none of it matters.
        var raw = text ?? string.Empty;
        var jsonStart = raw.IndexOf('{');
        var jsonEnd   = raw.LastIndexOf('}');

        if (jsonStart < 0 || jsonEnd <= jsonStart)
            throw new AIServiceException(
                $"AI returned no JSON object for word '{word}'. Raw: {raw[..Math.Min(200, raw.Length)]}");

        var json = raw[jsonStart..(jsonEnd + 1)];

        try
        {
            var data = JsonSerializer.Deserialize<WordData>(json, JsonOpts)
                ?? throw new AIServiceException("Deserialized WordData was null");
            if (string.IsNullOrWhiteSpace(data.Word))
            {
                data.Word = word;
                return data;
            }

            var requestedWord = NormalizeHeadword(word);
            var returnedWord = NormalizeHeadword(data.Word);
            if (requestedWord != returnedWord)
                throw new AIServiceException($"AI returned word '{data.Word}' for requested word '{word}'");

            data.Word = word;
            return data;
        }
        catch (JsonException ex)
        {
            throw new AIServiceException($"AI returned invalid JSON for word '{word}'", ex);
        }
    }

    private static string NormalizeHeadword(string word)
    {
        return word.Trim().ToLowerInvariant();
    }
}
