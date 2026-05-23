using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using LughatAI.Api.Models;

namespace LughatAI.Api.Services;

public class AIServiceException : Exception
{
    public AIServiceException(string message, Exception? inner = null) : base(message, inner) { }
}

public interface IWordAIService
{
    Task<WordData> GenerateWordAsync(string word, bool usePremium = false);
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
    }

    public async Task<WordData> GenerateWordAsync(string word, bool usePremium = false)
    {
        var model = usePremium
            ? _config["AI:LiveModel"] ?? "claude-sonnet-4-6"
            : _config["AI:BatchModel"] ?? "claude-haiku-4-5-20251001";

        try
        {
            var result = await CallClaudeAsync(word, model);
            result.Meta ??= new MetaInfo();
            result.Meta.GeneratedBy = "claude";
            result.Meta.GeneratedAt = DateTime.UtcNow.ToString("O");
            result.Meta.Model = model;
            return result;
        }
        catch (Exception claudeEx)
        {
            _logger.LogError(claudeEx, "Claude failed for word '{Word}', attempting OpenAI fallback", word);
            try
            {
                var result = await CallOpenAIAsync(word);
                result.Meta ??= new MetaInfo();
                result.Meta.GeneratedBy = "openai";
                result.Meta.GeneratedAt = DateTime.UtcNow.ToString("O");
                result.Meta.Model = "gpt-4o-mini";
                return result;
            }
            catch (Exception openAiEx)
            {
                _logger.LogError(openAiEx, "OpenAI fallback also failed for word '{Word}'", word);
                throw new AIServiceException($"All AI providers failed for word '{word}'", openAiEx);
            }
        }
    }

    private async Task<WordData> CallClaudeAsync(string word, string model)
    {
        var apiKey = _config["AI:AnthropicApiKey"]
            ?? throw new AIServiceException("Anthropic API key not configured");

        var payload = new
        {
            model,
            max_tokens = 4096,
            system = _systemPrompt,
            messages = new[] { new { role = "user", content = word } }
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

            return ParseWordData(text, word);
        }

        throw new AIServiceException("Claude returned 529 after retry");
    }

    private async Task<WordData> CallOpenAIAsync(string word)
    {
        var apiKey = _config["AI:OpenAIApiKey"]
            ?? throw new AIServiceException("OpenAI API key not configured");

        var payload = new
        {
            model = "gpt-4o-mini",
            max_tokens = 4096,
            messages = new[]
            {
                new { role = "system", content = _systemPrompt },
                new { role = "user", content = word }
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

        return ParseWordData(text, word);
    }

    public async Task<string?> InterpretRomanUrduAsync(string romanUrdu)
    {
        var apiKey = _config["AI:AnthropicApiKey"];
        if (string.IsNullOrEmpty(apiKey)) return null;

        var payload = new
        {
            model = _config["AI:LiveModel"] ?? "claude-sonnet-4-6",
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

    private WordData ParseWordData(string text, string word)
    {
        var json = text.Trim();
        // Strip markdown fences if present
        if (json.StartsWith("```"))
        {
            var start = json.IndexOf('\n') + 1;
            var end = json.LastIndexOf("```");
            if (end > start) json = json[start..end].Trim();
        }

        try
        {
            var data = JsonSerializer.Deserialize<WordData>(json, JsonOpts)
                ?? throw new AIServiceException("Deserialized WordData was null");
            if (string.IsNullOrEmpty(data.Word)) data.Word = word;
            return data;
        }
        catch (JsonException ex)
        {
            throw new AIServiceException($"AI returned invalid JSON for word '{word}'", ex);
        }
    }
}
