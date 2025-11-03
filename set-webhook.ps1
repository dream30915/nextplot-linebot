[CmdletBinding()]
Param(
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [string]$EnvPath = ".\.env"
)

$ErrorActionPreference = 'Stop'

function Read-Dotenv {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path $Path)) { throw ".env not found at $Path" }
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

Write-Host "Reading .env..." -ForegroundColor Cyan
$envMap = Read-Dotenv -Path $EnvPath
if (-not $envMap.ContainsKey('LINE_CHANNEL_ACCESS_TOKEN')) { throw 'LINE_CHANNEL_ACCESS_TOKEN not found in .env' }
$LINE_TOKEN = $envMap['LINE_CHANNEL_ACCESS_TOKEN']

Write-Host ("Setting webhook to: " + $Endpoint) -ForegroundColor Yellow
$headers = @{ Authorization = "Bearer $LINE_TOKEN"; 'Content-Type' = 'application/json' }
$body = @{ endpoint = $Endpoint } | ConvertTo-Json

try {
    Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/channel/webhook/endpoint' -Method Put -Headers $headers -Body $body | Out-Null
    Start-Sleep -Seconds 2
    $test = Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/channel/webhook/test' -Method Post -Headers $headers -Body $body
    Write-Host 'Webhook set and test invoked. Response:' -ForegroundColor Green
    $test | ConvertTo-Json -Compress | Write-Output
}
catch {
    Write-Warning ("Failed to set/test webhook: " + $_.Exception.Message)
    exit 1
}
