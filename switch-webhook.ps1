<#
switch-webhook.ps1
Simple script to switch LINE webhook endpoint between Cloud Run and Vercel.
Usage:
  .\switch-webhook.ps1 -Target cloudrun
  .\switch-webhook.ps1 -Target vercel
  .\switch-webhook.ps1 -Target status
#>

[CmdletBinding()]
param(
    [ValidateSet("cloudrun", "vercel", "status")]
    [string]$Target = "status",
    [string]$EnvPath = ".\.env"
)

$ErrorActionPreference = 'Stop'

function Read-Dotenv {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path $Path)) { Write-Error ".env not found at $Path"; return $result }
    foreach ($line in Get-Content $Path) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $parts = $l -split '=', 2
        if ($parts.Length -lt 2) { continue }
        $k = $parts[0].Trim()
        $v = $parts[1].Trim()
        if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $result[$k] = $v
    }
    return $result
}

$CLOUDRUN_URL = 'https://nextplot-linebot-656d4rnjja-as.a.run.app/api/line/webhook'
$VERCEL_URL = 'https://nextplotlinebot.vercel.app/api/line/webhook'

Write-Host 'Reading .env...' -ForegroundColor Cyan
$envMap = Read-Dotenv -Path $EnvPath
if (-not $envMap.ContainsKey('LINE_CHANNEL_ACCESS_TOKEN')) { Write-Error 'LINE_CHANNEL_ACCESS_TOKEN not found in .env'; exit 1 }
$LINE_TOKEN = $envMap['LINE_CHANNEL_ACCESS_TOKEN']

function Get-CurrentWebhook {
    param()
    try {
        $headers = @{ Authorization = "Bearer $LINE_TOKEN" }
        $info = Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/info' -Headers $headers -Method Get
        $endpoint = Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/channel/webhook/endpoint' -Headers $headers -Method Get
        return @{ BotName = $info.displayName; WebhookUrl = $endpoint.endpoint; Active = $endpoint.active }
    }
    catch {
        Write-Error "Failed to get current webhook: $($_.Exception.Message)"
        return $null
    }
}

function Set-WebhookUrl {
    param([string]$NewUrl)
    try {
        Write-Host "Setting webhook to: $NewUrl" -ForegroundColor Yellow
        $headers = @{ Authorization = "Bearer $LINE_TOKEN"; 'Content-Type' = 'application/json' }
        $body = @{ endpoint = $NewUrl } | ConvertTo-Json
        Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/channel/webhook/endpoint' -Method Put -Headers $headers -Body $body | Out-Null
        Start-Sleep -Seconds 2
        try {
            Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/channel/webhook/test' -Method Post -Headers $headers -Body $body | Out-Null
            Write-Host 'Webhook test OK' -ForegroundColor Green
            return $true
        }
        catch {
            Write-Warning "Webhook test failed: $($_.Exception.Message)"
            return $false
        }
    }
    catch {
        Write-Error "Failed to set webhook: $($_.Exception.Message)"
        return $false
    }
}

Write-Host ''
Write-Host 'NextPlot LINE Bot - Webhook Switcher' -ForegroundColor Cyan
Write-Host ''

$current = Get-CurrentWebhook
if ($null -eq $current) { Write-Error 'Cannot contact LINE API'; exit 1 }

Write-Host "Bot Name : $($current.BotName)" -ForegroundColor White
Write-Host "Webhook  : $($current.WebhookUrl)" -ForegroundColor White
Write-Host "Active   : $($current.Active)" -ForegroundColor White
Write-Host ''

if ($current.WebhookUrl -match 'cloud.*run|nextplot-linebot') { $currentTarget = 'cloudrun' }
elseif ($current.WebhookUrl -match 'vercel') { $currentTarget = 'vercel' }
elseif ($current.WebhookUrl -match 'cloudflare') { $currentTarget = 'cloudflare' }
else { $currentTarget = 'unknown' }

if ($Target -eq 'status') {
    Write-Host 'Usage:'
    Write-Host '  .\switch-webhook.ps1 -Target cloudrun'
    Write-Host '  .\switch-webhook.ps1 -Target vercel'
    exit 0
}

if ($Target -eq 'cloudrun') {
    if ($currentTarget -eq 'cloudrun') { Write-Host 'Already using Cloud Run'; exit 0 }
    $ok = Set-WebhookUrl -NewUrl $CLOUDRUN_URL
    if ($ok) { Write-Host 'Switched to Cloud Run' -ForegroundColor Green }
}
elseif ($Target -eq 'vercel') {
    if ($currentTarget -eq 'vercel') { Write-Host 'Already using Vercel'; exit 0 }
    $ok = Set-WebhookUrl -NewUrl $VERCEL_URL
    if ($ok) { Write-Host 'Switched to Vercel' -ForegroundColor Green }
}

Write-Host ''
