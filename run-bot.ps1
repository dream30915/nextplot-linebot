[CmdletBinding()]
param(
    [string]$FallbackLineToken = "",
    [string]$FallbackLineSecret = "",
    [int]$Port = 8000,
    [switch]$AutoPickPort
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}

function New-Directory([string]$p) { if (-not(Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Read-DotEnv([string]$key) {
    if (-not(Test-Path ".\.env")) { return "" }
    $m = Select-String -Path .\.env -Pattern ("^\s*{0}\s*=" -f [regex]::Escape($key)) | Select-Object -First 1
    if ($null -eq $m) { return "" }
    (($m.Line -split '=', 2)[1]).Trim().Trim('"').Trim("'")
}
function Set-DotEnvValues([hashtable]$pairs) {
    $f = ".\.env"; $txt = if (Test-Path $f) { [IO.File]::ReadAllText($f) } else { "" }
    foreach ($k in $pairs.Keys) {
        $v = [string]$pairs[$k]
        $v2 = $v -replace '"', '\"'
        $pat = "^{0}\s*=.*$" -f [regex]::Escape($k)
        if ([regex]::IsMatch($txt, $pat, 'Multiline')) {
            $txt = [regex]::Replace($txt, $pat, ("$k=""{0}""" -f $v2), 'Multiline')
        }
        else {
            if ([string]::IsNullOrWhiteSpace($txt)) { $txt = "$k=""$v2""" }
            else { $nl = [Environment]::NewLine; $txt = $txt.TrimEnd() + $nl + "$k=""$v2""" }
        }
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($f, $txt, $utf8)
}
function Test-PortOpen([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient; $iar = $c.BeginConnect("127.0.0.1", $p, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(150) -and $c.Connected) { $c.EndConnect($iar); $c.Close(); return $true }
        $c.Close(); return $false 
    }
    catch { return $false }
}
function Get-FreePort([int]$start) { $p = $start; for ($i = 0; $i -lt 200; $i++) { if (-not(Test-PortOpen $p)) { return $p }; $p++ }; throw "No free port" }
function Wait-Http([string]$url, [int]$max = 90) {
    $dl = (Get-Date).AddSeconds($max)
    do { try { Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 | Out-Null; return $true }catch { Start-Sleep -Milliseconds 700 } }while ((Get-Date) -lt $dl)
    return $false
}

# 1) .env
if (-not(Test-Path ".\.env") -and (Test-Path ".\.env.example")) { Copy-Item .\.env.example .\.env }
$tok = Read-DotEnv "LINE_CHANNEL_ACCESS_TOKEN"; if ([string]::IsNullOrWhiteSpace($tok)) { $tok = $FallbackLineToken }
$sec = Read-DotEnv "LINE_CHANNEL_SECRET"; if ([string]::IsNullOrWhiteSpace($sec)) { $sec = $FallbackLineSecret }
Set-DotEnvValues @{
    "APP_ENV" = "local"; "APP_DEBUG" = "true"; "APP_URL" = "http://127.0.0.1:$Port";
    "LINE_CHANNEL_ACCESS_TOKEN" = $tok; "LINE_CHANNEL_SECRET" = $sec; "LINE_SIGNATURE_RELAXED" = "true"
}

# 2) Port
if ($AutoPickPort) { $Port = Get-FreePort -start $Port }

# 3) Laravel
Start-Process -FilePath "php" -ArgumentList "artisan serve --host=127.0.0.1 --port=$Port" -NoNewWindow | Out-Null
[void](Wait-Http "http://127.0.0.1:$Port" 60)

# 4) cloudflared
function Find-Cloudflared() {
    $c = @("C:\Tools\cloudflared\cloudflared.exe", "$env:ProgramFiles\Cloudflare\cloudflared\cloudflared.exe", "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe", "$env:LOCALAPPDATA\cloudflared\cloudflared.exe", "$env:ProgramData\chocolatey\bin\cloudflared.exe")
    foreach ($p in $c) { if (Test-Path $p) { return $p } }
    $gc = Get-Command cloudflared -ErrorAction SilentlyContinue
    if ($gc -and (Test-Path $gc.Source)) { return $gc.Source }
    return ""
}
function Install-Cloudflared() {
    $target = "C:\Tools\cloudflared"; New-Directory $target
    $exe = Join-Path $target "cloudflared.exe"
    try {
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            winget install --id Cloudflare.cloudflared -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            $gc2 = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($gc2 -and (Test-Path $gc2.Source)) { return $gc2.Source }
        }
    }
    catch {}
    $api = "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "PowerShell" }
    $asset = $rel.assets | Where-Object { $_.name -match 'cloudflared-windows-amd64\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw "Cannot locate windows-amd64 exe" }
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $exe -UseBasicParsing
    try { setx PATH (($env:Path + ";" + (Split-Path -Parent $exe)) -replace ';;', ';') | Out-Null }catch {}
    return $exe
}
$cf = Find-Cloudflared
if (-not $cf) { $cf = Install-Cloudflared }
if (-not(Test-Path $cf)) { throw "cloudflared not found after install." }

# 5) Tunnel + URL
$log = Join-Path $env:TEMP ("cloudflared-" + (Get-Date -Format "yyyyMMddHHmmss") + ".log")
$cfArgs = @("tunnel", "--ha-connections", "2", "--no-autoupdate", "--url", "http://127.0.0.1:$Port", "--logfile", $log, "--metrics", "127.0.0.1:0")
Start-Process -FilePath $cf -ArgumentList $cfArgs -WindowStyle Hidden | Out-Null
$publicUrl = ""
$deadline = (Get-Date).AddSeconds(120)
$regex = 'https://[a-z0-9-]+\.trycloudflare\.com'
do {
    if (Test-Path $log) {
        $txt = Get-Content -Raw $log
        if ($txt -match $regex) { $publicUrl = $matches[0]; break }
    }
    Start-Sleep -Milliseconds 500
}while ((Get-Date) -lt $deadline)
if ([string]::IsNullOrWhiteSpace($publicUrl)) { Write-Warning "Public URL not ready. Log: $log" }

# 6) LINE webhook
function Test-LineToken($token) { try { Invoke-RestMethod -Method Get "https://api.line.me/v2/bot/info" -Headers @{ Authorization = "Bearer $token" } | Out-Null; return $true }catch { return $false } }
function Set-LineWebhook($token, $url) { $h = @{ Authorization = "Bearer $token" }; $b = @{ endpoint = $url } | ConvertTo-Json -Compress; Invoke-RestMethod -Method Put "https://api.line.me/v2/bot/channel/webhook/endpoint" -Headers $h -ContentType "application/json" -Body $b | Out-Null }
function Test-LineWebhook($token, $url) { $h = @{ Authorization = "Bearer $token" }; $b = @{ endpoint = $url } | ConvertTo-Json -Compress; try { $r = Invoke-RestMethod -Method Post "https://api.line.me/v2/bot/channel/webhook/test" -Headers $h -ContentType "application/json" -Body $b; return ($r.success -eq $true) }catch { return $false } }
$token = Read-DotEnv "LINE_CHANNEL_ACCESS_TOKEN"; if ([string]::IsNullOrWhiteSpace($token)) { $token = $FallbackLineToken }
if ($publicUrl -and (Test-LineToken $token)) {
    $wb = "$publicUrl/api/line/webhook"
    try { Set-LineWebhook $token $wb; $ok = Test-LineWebhook $token $wb }catch { $ok = $false }
    Write-Host "Public URL: $publicUrl"
    Write-Host "Webhook:    $wb"
    if ($ok) { Write-Host "LINE webhook test: success" } else { Write-Warning "LINE webhook test did not confirm success yet." }
}
else {
    if (-not $publicUrl) { Write-Warning "No Public URL (cloudflared). Log: $log" }
    if (-not (Test-LineToken $token)) { Write-Warning "LINE token invalid/unreachable." }
}

# 7) Silent pings
try { (Invoke-WebRequest "http://127.0.0.1:$Port/api/nextplot/search?q=ping" -TimeoutSec 10) | Out-Null }catch {}
if ($publicUrl) {
    try { (Invoke-WebRequest "$publicUrl/api/nextplot/search?q=ping" -TimeoutSec 10) | Out-Null }catch {}
    try { (Invoke-WebRequest -Method Post "$publicUrl/api/line/webhook" -ContentType "application/json" -Body '{"events":[]}' -TimeoutSec 10) | Out-Null }catch {}
}
Write-Host "All set."