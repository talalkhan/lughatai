# Configuration Reference

> Local config templates. Production values live in Azure App Service settings (see DEPLOYMENT.md). Never commit secrets.

## Environment Variables

Create `api/appsettings.Development.json` (never commit secrets):

```json
{
  "ConnectionStrings": {
    "Default": "Host=localhost;Port=5433;Database=lughatai;Username=postgres;Password=postgres"
  },
  "Redis": {
    "Connection": "localhost:6379"
  },
  "AI": {
    "AnthropicApiKey": "YOUR_KEY",
    "OpenAIApiKey": "YOUR_KEY",
    "BatchModel": "claude-haiku-4-5",
    "LiveModel": "claude-sonnet-4-6"
  },
  "Azure": {
    "SpeechKey": "",
    "SpeechRegion": "",
    "BlobConnection": ""
  },
  "ApplicationInsights": {
    "ConnectionString": ""  // leave empty for local dev; set in Azure App Service config
  },
  "Jwt": {
    "Secret": "dev-secret-min-32-chars-long-here",
    "ExpiryHours": 1,
    "RefreshExpiryDays": 30
  },
  "Cors": {
    "AllowedOrigins": ["http://localhost:3000"]
  },
  "WordGeneration": {
    "Enabled": false,
    "RequireApprovedWord": true
  },
  "Enrichment": {
    "Enabled": true,
    "MaxPerHour": 30
  },
  "Notifications": {
    "Email": {
      "Enabled": true,                         // false in production appsettings.json; flip on per-env
      "SmtpHost": "smtp.gmail.com",
      "SmtpPort": 587,
      "SmtpUsername": "urdumeaningreport@gmail.com",
      "SmtpPassword": "GMAIL_APP_PASSWORD",    // 16-char App Password, NOT the account password
      "From": "urdumeaningreport@gmail.com",
      "To": "admin@thetafoundry.com",
      "SiteBaseUrl": "http://localhost:3000"   // production overrides to https://urdumeaning.com
    }
  }
}
```

Create `web/.env.local`:
```
NEXT_PUBLIC_API_URL=http://localhost:5000
NEXT_PUBLIC_SITE_URL=https://urdumeaning.com
NEXT_PUBLIC_GA_MEASUREMENT_ID=
NEXT_PUBLIC_PLAUSIBLE_DOMAIN=
GOOGLE_SITE_VERIFICATION=
BING_SITE_VERIFICATION=
```

---

