using System.Net;
using System.Net.Mail;

namespace UrduMeaning.Api.Services;

public interface IReportNotificationService
{
    /// <summary>
    /// Fire-and-forget — sends an email about a new word report.
    /// Never throws; failures are logged and swallowed so the flag endpoint
    /// can't be broken by a misconfigured email provider.
    /// </summary>
    Task NotifyAsync(
        string word,
        string reason,
        string? notes,
        int? userId,
        string? definitionModel,
        DateTime? definitionUpdatedAt,
        string? primaryUrdu);
}

/// <summary>
/// Sends report notifications via SMTP (currently Gmail).
/// Uses System.Net.Mail.SmtpClient — built into .NET, no NuGet package needed.
///
/// Gmail SMTP requires an App Password (not your regular Gmail password).
/// Generate one at https://myaccount.google.com/apppasswords with 2FA enabled.
/// Gmail free-tier daily limit: ~500 emails/day.
///
/// Config (appsettings + env-var overrides):
///   Notifications:Email:Enabled       — master on/off
///   Notifications:Email:SmtpHost      — e.g. "smtp.gmail.com"
///   Notifications:Email:SmtpPort      — 587 (STARTTLS) recommended
///   Notifications:Email:SmtpUsername  — the Gmail address sending the mail
///   Notifications:Email:SmtpPassword  — 16-char Gmail App Password (set via env var in Azure)
///   Notifications:Email:From          — sender address shown in the email
///   Notifications:Email:To            — admin inbox to receive reports
///   Notifications:Email:SiteBaseUrl   — used to build the word page deep link
///
/// If Enabled=false or any required field is missing, this no-ops without throwing.
/// </summary>
public class ReportNotificationService : IReportNotificationService
{
    private readonly IConfiguration _config;
    private readonly ILogger<ReportNotificationService> _logger;

    public ReportNotificationService(
        IConfiguration config,
        ILogger<ReportNotificationService> logger)
    {
        _config = config;
        _logger = logger;
    }

    public async Task NotifyAsync(
        string word,
        string reason,
        string? notes,
        int? userId,
        string? definitionModel,
        DateTime? definitionUpdatedAt,
        string? primaryUrdu)
    {
        try
        {
            var section = _config.GetSection("Notifications:Email");
            if (!section.GetValue<bool>("Enabled", false))
                return;

            var host = section["SmtpHost"];
            var port = section.GetValue<int>("SmtpPort", 587);
            var username = section["SmtpUsername"];
            var password = section["SmtpPassword"];
            var from = section["From"];
            var to = section["To"];
            var siteBaseUrl = section["SiteBaseUrl"] ?? "https://urdumeaning.com";

            if (string.IsNullOrWhiteSpace(host) ||
                string.IsNullOrWhiteSpace(username) ||
                string.IsNullOrWhiteSpace(password) ||
                string.IsNullOrWhiteSpace(from) ||
                string.IsNullOrWhiteSpace(to))
            {
                _logger.LogWarning(
                    "Report email skipped — Notifications:Email is Enabled but SMTP host/credentials/from/to is not set.");
                return;
            }

            var wordUrl = $"{siteBaseUrl.TrimEnd('/')}/word/{Uri.EscapeDataString(word)}";
            var who = userId.HasValue ? $"user #{userId.Value}" : "anonymous";
            var safeNotes = string.IsNullOrWhiteSpace(notes) ? "(none)" : notes;
            var model = string.IsNullOrWhiteSpace(definitionModel) ? "(unknown)" : definitionModel;
            var updatedAt = definitionUpdatedAt?.ToString("O") ?? "(unknown)";
            var urdu = string.IsNullOrWhiteSpace(primaryUrdu) ? "(unknown)" : primaryUrdu;

            var subject = $"[UrduMeaning] Report on \"{word}\" — {reason}";
            var text =
                $"A new report was submitted on urdumeaning.com.\n\n" +
                $"Word:   {word}\n" +
                $"Urdu:   {urdu}\n" +
                $"Reason: {reason}\n" +
                $"Notes:  {safeNotes}\n" +
                $"Model:  {model}\n" +
                $"Definition updated at: {updatedAt}\n" +
                $"User:   {who}\n\n" +
                $"View word: {wordUrl}\n" +
                $"Review queue: {siteBaseUrl.TrimEnd('/')}/api/admin/corrections\n";

            var html =
                "<div style=\"font-family:system-ui,-apple-system,sans-serif;max-width:520px\">" +
                "<h2 style=\"margin:0 0 12px\">🚩 New word report</h2>" +
                "<table style=\"border-collapse:collapse;font-size:14px\">" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">Word</td><td><a href=\"{wordUrl}\">{System.Net.WebUtility.HtmlEncode(word)}</a></td></tr>" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">Urdu</td><td>{System.Net.WebUtility.HtmlEncode(urdu)}</td></tr>" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">Reason</td><td><strong>{System.Net.WebUtility.HtmlEncode(reason)}</strong></td></tr>" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">Notes</td><td>{System.Net.WebUtility.HtmlEncode(safeNotes)}</td></tr>" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">Model</td><td>{System.Net.WebUtility.HtmlEncode(model)}</td></tr>" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">Definition updated</td><td>{System.Net.WebUtility.HtmlEncode(updatedAt)}</td></tr>" +
                $"<tr><td style=\"padding:4px 12px 4px 0;color:#666\">User</td><td>{System.Net.WebUtility.HtmlEncode(who)}</td></tr>" +
                "</table>" +
                $"<p style=\"margin-top:16px\"><a href=\"{wordUrl}\" style=\"background:#059669;color:#fff;padding:8px 14px;border-radius:6px;text-decoration:none\">Open word page</a></p>" +
                "</div>";

            using var smtp = new SmtpClient(host, port)
            {
                EnableSsl = true,
                DeliveryMethod = SmtpDeliveryMethod.Network,
                UseDefaultCredentials = false,
                // App passwords from Google are shown with spaces ("abcd efgh ijkl mnop"); strip them so the credential always matches.
                Credentials = new NetworkCredential(username, password.Replace(" ", "")),
                Timeout = 10_000
            };

            using var message = new MailMessage
            {
                From = new MailAddress(from, "UrduMeaning Reports"),
                Subject = subject,
                Body = html,
                IsBodyHtml = true
            };
            message.To.Add(to);
            // AlternateView with plain-text body so non-HTML mail clients still render cleanly.
            message.AlternateViews.Add(AlternateView.CreateAlternateViewFromString(
                text, null, "text/plain"));
            message.AlternateViews.Add(AlternateView.CreateAlternateViewFromString(
                html, null, "text/html"));

            await smtp.SendMailAsync(message);
            _logger.LogInformation("Report email sent for '{Word}' ({Reason})", word, reason);
        }
        catch (Exception ex)
        {
            // Never let an email failure surface to the user-facing flag endpoint.
            _logger.LogWarning(ex, "Failed to send report notification for '{Word}'", word);
        }
    }
}
