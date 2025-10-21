# NextPlot LINE Bot - Diagnostic Script
# ตรวจสอบสถานะทุกอย่างของ LINE Bot

param(
    [switch]$ShowSecrets = $false
)

Write-Host "`n=== NextPlot LINE Bot Diagnostics ===" -ForegroundColor Cyan
Write-Host "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Gray

# 1. Check .env file
Write-Host "[1] Checking .env configuration..." -ForegroundColor Yellow
if (Test-Path .env) {
    $env_content = Get-Content .env -Raw
    
    $required_keys = @(
        "APP_KEY",
        "LINE_CHANNEL_ACCESS_TOKEN",
        "LINE_CHANNEL_SECRET",
        "SUPABASE_URL",
        "SUPABASE_SERVICE_ROLE"
    )
    
    $all_present = $true
    foreach ($key in $required_keys) {
        if ($env_content -match "$key=") {
            $value = ($env_content -split "`n" | Where-Object { $_ -match "^$key=" }) -replace "$key=", "" -replace '"', ''
            if ($ShowSecrets) {
                Write-Host "  ✓ $key = $value" -ForegroundColor Green
            }
            else {
                $masked = if ($value.Length -gt 10) { $value.Substring(0, 10) + "..." } else { "***" }
                Write-Host "  ✓ $key = $masked" -ForegroundColor Green
            }
        }
        else {
            Write-Host "  ✗ $key = MISSING" -ForegroundColor Red
            $all_present = $false
        }
    }
    
    if ($all_present) {
        Write-Host "  ✓ All required keys present" -ForegroundColor Green
    }
}
else {
    Write-Host "  ✗ .env file not found!" -ForegroundColor Red
}

# 2. Check Secret Manager secrets
Write-Host "`n[2] Checking Secret Manager secrets..." -ForegroundColor Yellow
$secrets = @("APP_KEY", "LINE_CHANNEL_ACCESS_TOKEN", "LINE_CHANNEL_SECRET", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE")
foreach ($secret in $secrets) {
    try {
        $result = gcloud secrets versions list $secret --limit=1 2>&1
        if ($LASTEXITCODE -eq 0) {
            $version = ($result | Select-String -Pattern "^\d+").Matches.Value | Select-Object -First 1
            Write-Host "  ✓ $secret (version: $version)" -ForegroundColor Green
        }
        else {
            Write-Host "  ✗ $secret - Not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ $secret - Error checking" -ForegroundColor Red
    }
}

# 3. Check Cloud Run service
Write-Host "`n[3] Checking Cloud Run service..." -ForegroundColor Yellow
try {
    $service = gcloud run services describe nextplot-linebot --region asia-southeast1 --format=json 2>&1 | ConvertFrom-Json
    if ($service) {
        $url = $service.status.url
        $revision = $service.status.latestReadyRevisionName
        $traffic = $service.status.traffic[0].percent
        
        Write-Host "  ✓ Service: nextplot-linebot" -ForegroundColor Green
        Write-Host "  ✓ URL: $url" -ForegroundColor Green
        Write-Host "  ✓ Revision: $revision" -ForegroundColor Green
        Write-Host "  ✓ Traffic: $traffic%" -ForegroundColor Green
        
        # Check if secrets are properly configured
        $containers = $service.spec.template.spec.containers[0]
        $secrets_configured = $containers.env | Where-Object { $_.valueFrom.secretKeyRef } | Measure-Object
        Write-Host "  ✓ Secrets configured: $($secrets_configured.Count)" -ForegroundColor Green
    }
}
catch {
    Write-Host "  ✗ Failed to get Cloud Run service info" -ForegroundColor Red
}

# 4. Check LINE webhook configuration
Write-Host "`n[4] Checking LINE webhook..." -ForegroundColor Yellow
if (Test-Path .env) {
    $token = (Get-Content .env | Where-Object { $_ -match "^LINE_CHANNEL_ACCESS_TOKEN=" }) -replace 'LINE_CHANNEL_ACCESS_TOKEN=', '' -replace '"', ''
    
    try {
        $headers = @{
            "Authorization" = "Bearer $token"
        }
        $response = Invoke-RestMethod -Uri "https://api.line.me/v2/bot/info" -Headers $headers -Method Get
        
        Write-Host "  ✓ Bot Name: $($response.displayName)" -ForegroundColor Green
        Write-Host "  ✓ Bot ID: $($response.userId)" -ForegroundColor Green
        
        # Get webhook endpoint
        $webhook = Invoke-RestMethod -Uri "https://api.line.me/v2/bot/channel/webhook/endpoint" -Headers $headers -Method Get
        Write-Host "  ✓ Webhook: $($webhook.endpoint)" -ForegroundColor Green
        Write-Host "  ✓ Active: $($webhook.active)" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to get LINE bot info: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 5. Test Cloud Run endpoint
Write-Host "`n[5] Testing Cloud Run endpoint..." -ForegroundColor Yellow
$cloud_run_url = "https://nextplot-linebot-656d4rnjja-as.a.run.app"

try {
    $response = Invoke-WebRequest -Uri "$cloud_run_url/api/line/webhook" -Method Get -UseBasicParsing
    Write-Host "  ✓ Cloud Run responding (Status: $($response.StatusCode))" -ForegroundColor Green
}
catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 405) {
        Write-Host "  ✓ Cloud Run responding (405 Method Not Allowed - expected for GET)" -ForegroundColor Green
    }
    else {
        Write-Host "  ⚠ Cloud Run status: $statusCode" -ForegroundColor Yellow
    }
}

# 6. Check recent logs
Write-Host "`n[6] Checking recent Cloud Run logs..." -ForegroundColor Yellow
Write-Host "  Fetching last 5 log entries..." -ForegroundColor Gray
try {
    $logs = gcloud run services logs read nextplot-linebot --region asia-southeast1 --limit=5 2>&1
    Write-Host $logs -ForegroundColor Gray
}
catch {
    Write-Host "  ✗ Failed to fetch logs" -ForegroundColor Red
}

# 7. Check Supabase connection
Write-Host "`n[7] Testing Supabase connection..." -ForegroundColor Yellow
if (Test-Path .env) {
    $supabase_url = (Get-Content .env | Where-Object { $_ -match "^SUPABASE_URL=" }) -replace 'SUPABASE_URL=', '' -replace '"', ''
    $supabase_key = (Get-Content .env | Where-Object { $_ -match "^SUPABASE_ANON_KEY=" }) -replace 'SUPABASE_ANON_KEY=', '' -replace '"', ''
    $bucket = (Get-Content .env | Where-Object { $_ -match "^SUPABASE_BUCKET_NAME=" }) -replace 'SUPABASE_BUCKET_NAME=', '' -replace '"', ''
    
    try {
        $headers = @{
            "apikey"        = $supabase_key
            "Authorization" = "Bearer $supabase_key"
        }
        $response = Invoke-RestMethod -Uri "$supabase_url/storage/v1/bucket/$bucket" -Headers $headers -Method Get
        Write-Host "  ✓ Supabase bucket '$bucket' accessible" -ForegroundColor Green
        Write-Host "  ✓ Bucket public: $($response.public)" -ForegroundColor Green
    }
    catch {
        Write-Host "  ✗ Failed to connect to Supabase: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Diagnostic Complete ===" -ForegroundColor Cyan
Write-Host "Run with -ShowSecrets to display full secret values`n" -ForegroundColor Gray
