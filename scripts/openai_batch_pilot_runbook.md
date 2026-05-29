# OpenAI Batch Pilot Runbook

Goal: safely populate a small set of missing production words while preserving the OpenAI credit balance.

## Safety rules

- Do not enable Azure `BatchProcessor__Enabled` for bulk loading.
- Use OpenAI Batch API, not the hosted queue processor, for lower cost and better control.
- Use a pilot-specific tracking file; do not reuse `scripts/words/processed/openai_batches.json`.
- Keep `WordGeneration__RequireApprovedWord=true`.
- Collect to Azure only after the OpenAI batch status is `completed`.
- Pass the Azure PostgreSQL connection string explicitly with `LUGHATAI_AZURE_PG_CONN` or `-AzureConnStr`.

## Current pilot list

The curated, frequency-validated, production-missing pilot list is:

```text
scripts/words/processed/pilot_missing_500.txt
```

It currently contains 127 words.

## Step 1: prepare local queue only

This does not call OpenAI and does not write to Azure.

```powershell
.\scripts\prepare_openai_pilot_queue.ps1 `
  -File scripts\words\processed\pilot_missing_500.txt `
  -Priority 1
```

## Step 2: submit one isolated OpenAI Batch job

This is the first point where OpenAI credit can be spent.

```powershell
.\scripts\batch_submit_openai.ps1 `
  -LimitWords 127 `
  -RequestsPerBatch 127 `
  -MaxPriority 1 `
  -TrackingFile scripts\words\processed\openai_batches_pilot_20260529.json `
  -TempDir scripts\words\processed\batch_temp_pilot_20260529 `
  -MinBalanceUsd 24 `
  -TestOne
```

## Step 3: monitor only

```powershell
.\scripts\batch_collect_openai.ps1 `
  -TrackingFile scripts\words\processed\openai_batches_pilot_20260529.json `
  -TempDir scripts\words\processed\batch_temp_pilot_20260529 `
  -StatusOnly
```

## Step 4: collect to local and Azure

Only run this after the batch is completed.

```powershell
$env:LUGHATAI_AZURE_PG_CONN = "<production-postgres-connection-string>"

.\scripts\batch_collect_openai.ps1 `
  -TrackingFile scripts\words\processed\openai_batches_pilot_20260529.json `
  -TempDir scripts\words\processed\batch_temp_pilot_20260529 `
  -AzureDb
```

## Step 5: verify

Check a few generated words:

```powershell
curl.exe -s https://lughatai-beta-api.azurewebsites.net/api/word/centralized
curl.exe -s https://lughatai-beta-api.azurewebsites.net/api/word/cerebellum
curl.exe -s https://lughatai-beta-api.azurewebsites.net/api/word/circumvent
```

Then check actual OpenAI spend before preparing the next batch.
