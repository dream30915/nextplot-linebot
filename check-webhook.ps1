[CmdletBinding()]
Param(
    [string]$EnvPath = ""
)
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($EnvPath)) { $EnvPath = Join-Path $PSScriptRoot ".env" }
if (-not (Test-Path -LiteralPath $EnvPath)) { throw ".env not found at $EnvPath" }

$envText = Get-Content -Raw -LiteralPath $EnvPath
$m = [regex]::Match($envText, '(?m)^\s*LINE_CHANNEL_ACCESS_TOKEN\s*=\s*(.+)\s*$')
if (-not $m.Success) { throw "LINE_CHANNEL_ACCESS_TOKEN not found in .env" }
$t = $m.Groups[1].Value.Trim().Trim('"').Trim("'")
if ([string]::IsNullOrWhiteSpace($t)) { throw "Token read from .env is empty" }

$wbObj = Invoke-RestMethod -Method Get 'https://api.line.me/v2/bot/channel/webhook/endpoint' -Headers @{ Authorization = "Bearer $t" }
$wb = $wbObj.endpoint
Write-Host ("Webhook from API: " + $wb)

$test = Invoke-RestMethod -Method Post 'https://api.line.me/v2/bot/channel/webhook/test' -Headers @{ Authorization = "Bearer $t" } -ContentType 'application/json' -Body (@{ endpoint = $wb } | ConvertTo-Json -Compress)
$test | ConvertTo-Json -Compress