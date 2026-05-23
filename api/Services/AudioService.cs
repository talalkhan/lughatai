using Azure.Storage.Blobs;
using Azure.Storage.Blobs.Models;
using LughatAI.Api.Data;
using LughatAI.Api.Models;
using System.Security;

namespace LughatAI.Api.Services;

public interface IAudioService
{
    /// <summary>
    /// Returns the CDN/Blob URL for the word's audio in the requested language.
    /// Generates and uploads the audio on first request (lazy).
    /// </summary>
    Task<string?> GetOrGenerateAsync(string word, WordData data, string lang);
}

public class AudioService : IAudioService
{
    private readonly IHttpClientFactory _http;
    private readonly IConfiguration _config;
    private readonly IWordRepository _repository;
    private readonly ICacheService _cache;
    private readonly ILogger<AudioService> _logger;

    public AudioService(
        IHttpClientFactory http,
        IConfiguration config,
        IWordRepository repository,
        ICacheService cache,
        ILogger<AudioService> logger)
    {
        _http = http;
        _config = config;
        _repository = repository;
        _cache = cache;
        _logger = logger;
    }

    public async Task<string?> GetOrGenerateAsync(string word, WordData data, string lang)
    {
        // Return cached URL if present
        var existingUrl = lang == "en" ? data.Audio?.EnUrl : data.Audio?.UrUrl;
        if (!string.IsNullOrEmpty(existingUrl))
            return existingUrl;

        var speechKey = _config["Azure:SpeechKey"];
        var blobConnection = _config["Azure:BlobConnection"];
        if (string.IsNullOrEmpty(speechKey) || string.IsNullOrEmpty(blobConnection))
        {
            _logger.LogWarning("Audio generation skipped: Azure Speech or Blob not configured");
            return null;
        }

        var audioBytes = await GenerateTtsAsync(word, data, lang);
        if (audioBytes == null) return null;

        var url = await UploadToBlobAsync(word, lang, audioBytes, blobConnection);
        if (url == null) return null;

        // Persist URL to DB and invalidate Redis
        var wordLower = word.Trim().ToLowerInvariant();
        await _repository.UpdateAudioUrlAsync(wordLower, lang, url);
        await _cache.InvalidateWordAsync(wordLower);

        return url;
    }

    private async Task<byte[]?> GenerateTtsAsync(string word, WordData data, string lang)
    {
        var region = _config["Azure:SpeechRegion"] ?? "eastus";
        var key = _config["Azure:SpeechKey"]!;

        var (voiceName, xmlLang, textToSpeak) = lang == "en"
            ? ("en-US-JennyNeural", "en-US", word)
            : ("ur-PK-UzmaNeural", "ur-PK", data.ScriptVariants?.Nastaliq ?? word);

        var safeText = SecurityElement.Escape(textToSpeak) ?? textToSpeak;
        var ssml = $"""
            <speak version='1.0' xml:lang='{xmlLang}'>
                <voice name='{voiceName}'>{safeText}</voice>
            </speak>
            """;

        var client = _http.CreateClient("speech");
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1");

        request.Headers.Add("Ocp-Apim-Subscription-Key", key);
        request.Headers.Add("X-Microsoft-OutputFormat", "audio-16khz-128kbitrate-mono-mp3");
        request.Headers.Add("User-Agent", "LughatAI/1.0");
        request.Content = new StringContent(ssml, System.Text.Encoding.UTF8, "application/ssml+xml");

        HttpResponseMessage response;
        try
        {
            response = await client.SendAsync(request);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "TTS HTTP request failed for word '{Word}' lang '{Lang}'", word, lang);
            return null;
        }

        if (!response.IsSuccessStatusCode)
        {
            _logger.LogError("TTS failed: {StatusCode} for word '{Word}' lang '{Lang}'",
                response.StatusCode, word, lang);
            return null;
        }

        return await response.Content.ReadAsByteArrayAsync();
    }

    private async Task<string?> UploadToBlobAsync(string word, string lang, byte[] audioBytes, string blobConnection)
    {
        const string containerName = "audio";
        var blobName = $"{word.Trim().ToLowerInvariant()}/{lang}.mp3";
        var cdnBaseUrl = _config["Azure:CdnBaseUrl"];

        try
        {
            var serviceClient = new BlobServiceClient(blobConnection);
            var containerClient = serviceClient.GetBlobContainerClient(containerName);
            await containerClient.CreateIfNotExistsAsync(PublicAccessType.Blob);

            var blobClient = containerClient.GetBlobClient(blobName);
            using var stream = new MemoryStream(audioBytes);
            await blobClient.UploadAsync(stream, new BlobUploadOptions
            {
                HttpHeaders = new BlobHttpHeaders { ContentType = "audio/mpeg" }
            });

            return !string.IsNullOrEmpty(cdnBaseUrl)
                ? $"{cdnBaseUrl.TrimEnd('/')}/audio/{blobName}"
                : blobClient.Uri.ToString();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Blob upload failed for word '{Word}' lang '{Lang}'", word, lang);
            return null;
        }
    }
}
