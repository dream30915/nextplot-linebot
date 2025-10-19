[CmdletBinding()]
param(
    [string]$LineToken = "",
    [string]$LineSecret = "",
    [int]$Port = 8000,
    [switch]$AutoPickPort,
    [string]$PhpHost = "127.0.0.1",
    [string]$CloudflaredPath = ""   # full path to cloudflared.exe (optional)
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== Utilities =====
function Get-EnvNormalized([string]$s) {
    if ($null -eq $s) { return "" }
    $t = $s.Trim()
    $t = $t -replace "[\r\n]", ""
    $t = $t -replace "^[<]+|[>]+$", ""
    return $t
}

function Set-DotenvKey([string]$Text, [string]$Key, [string]$Value) {
    if ($null -eq $Text) { $Text = "" }
    if ($null -eq $Value) { $Value = "" }
    $escaped = $Value -replace '"', '\"'
    $pattern = "^{0}\s*=.*$" -f [regex]::Escape($Key)
    if ([regex]::IsMatch($Text, $pattern, 'Multiline')) {
        return [regex]::Replace($Text, $pattern, ("$Key=""{0}""" -f $escaped), 'Multiline')
    }
    else {
        if ([string]::IsNullOrWhiteSpace($Text)) { return "$Key=""$escaped""" }
        else {
            $nl = [Environment]::NewLine
            return ($Text.TrimEnd() + $nl + "$Key=""$escaped""")
        }
    }
}

function Get-DotenvValue([string]$Key) {
    if (-not(Test-Path ".\.env")) { return "" }
    $line = Select-String -Path .\.env -Pattern ("^\s*{0}\s*=" -f [regex]::Escape($Key)) | Select-Object -First 1
    if ($null -eq $line) { return "" }
    $val = ($line.Line -split '=', 2)[1]
    return $val.Trim().Trim('"').Trim("'")
}

function Test-NeedsReplacement([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return $true }
    if ($v -match '^\s*<.+>\s*$') { return $true }
    if ($v -match '^\s*(PASTE_|YOUR_|TOKEN|SECRET)') { return $true }
    return $false
}

function Set-EnvSmart([string]$Tok, [string]$Sec) {
    $envFile = ".\.env"
    if (-not(Test-Path $envFile) -and (Test-Path ".\.env.example")) {
        Copy-Item ".\.env.example" $envFile
    }
    $content = ""
    if (Test-Path $envFile) { $content = [System.IO.File]::ReadAllText($envFile) }

    $curTok = Get-DotenvValue "LINE_CHANNEL_ACCESS_TOKEN"
    $curSec = Get-DotenvValue "LINE_CHANNEL_SECRET"

    if (Test-NeedsReplacement $curTok -and -not [string]::IsNullOrWhiteSpace($Tok)) {
        $content = Set-DotenvKey -Text $content -Key "LINE_CHANNEL_ACCESS_TOKEN" -Value $Tok
    }
    if (Test-NeedsReplacement $curSec -and -not [string]::IsNullOrWhiteSpace($Sec)) {
        $content = Set-DotenvKey -Text $content -Key "LINE_CHANNEL_SECRET" -Value $Sec
    }
    $content = Set-DotenvKey -Text $content -Key "LINE_SIGNATURE_RELAXED" -Value "true"

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($envFile, $content, $utf8)
    Write-Information ".env updated."
}

function Test-PortOpen([int]$p) {
    try {
        $c = New-Object System.Net.Sockets.TcpClient
        $iar = $c.BeginConnect("127.0.0.1", $p, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne(150) -and $c.Connected) { $c.EndConnect($iar); $c.Close(); return $true }
        $c.Close(); return $false
    }
    catch { return $false }
}

function Get-FreePort([int]$start) {
    $p = $start
    for ($i = 0; $i -lt 200; $i++) {
        if (-not (Test-PortOpen $p)) { return $p }
        $p++
    }
    throw "No free port found starting at $start"
}

function Wait-HttpReady([string]$url, [int]$maxSec = 90) {
    $deadline = (Get-Date).AddSeconds($maxSec)
    do {
        try { Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 | Out-Null; return $true }
        catch { Start-Sleep -Milliseconds 700 }
    } while ((Get-Date) -lt $deadline)
    return $false
}

# ===== cloudflared locate/install =====
function Search-CloudflaredExe([string]$Hint) {
    if ($Hint -and (Test-Path $Hint)) { return $Hint }

    $candidates = @(
        "C:\Tools\cloudflared\cloudflared.exe",
        "$env:ProgramFiles\Cloudflare\cloudflared\cloudflared.exe",
        "$env:ProgramFiles\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\cloudflared\cloudflared.exe",
        "$env:ProgramData\chocolatey\bin\cloudflared.exe",
        "C:\Windows\System32\cloudflared.exe"
    )

    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }

    $gc = (Get-Command cloudflared -ErrorAction SilentlyContinue)
    if ($gc -and (Test-Path $gc.Source)) { return $gc.Source }

    foreach ($d in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")) {
        $p = Join-Path $d "cloudflared.exe"
        if (Test-Path $p) { return $p }
    }
    return ""
}

function Install-Cloudflared([string]$TargetDir = "C:\Tools\cloudflared") {
    function New-Dir([string]$p) { if (-not(Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }
    New-Dir $TargetDir
    $exe = Join-Path $TargetDir "cloudflared.exe"

    # Try winget silent
    try {
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            winget install --id Cloudflare.cloudflared -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            $gc2 = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($gc2 -and (Test-Path $gc2.Source)) { return $gc2.Source }
        }
    }
    catch { Write-Warning "winget failed: $($_.Exception.Message)" }

    # Fallback: download latest release
    $api = "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
    Write-Information "Downloading cloudflared from GitHub releases..."
    $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "PowerShell" }
    $asset = $rel.assets | Where-Object { $_.name -match 'cloudflared-windows-amd64\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw "Could not find windows-amd64 .exe in latest release assets." }
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $exe -UseBasicParsing

    try { setx PATH (($env:Path + ";" + (Split-Path -Parent $exe)) -replace ';;', ';') | Out-Null } catch {}
    return $exe
}

function Get-CloudflaredExe([string]$Hint) {
    $found = Search-CloudflaredExe -Hint $Hint
    if ($found) { return $found }
    return Install-Cloudflared
}

function Start-Cloudflared([string]$CfExe, [string]$LocalUrl) {
    $log = Join-Path $env:TEMP ("cloudflared-" + (Get-Date -Format "yyyyMMddHHmmss") + ".log")
    $cfArgs = @(
        "tunnel",
        "--ha-connections", "2",
        "--no-autoupdate",
        "--url", $LocalUrl,
        "--logfile", $log,
        "--metrics", "127.0.0.1:0"
    )
    Write-Information "Starting cloudflared quick tunnel for $LocalUrl ..."
    $proc = Start-Process -FilePath $CfExe -ArgumentList $cfArgs -WindowStyle Hidden -PassThru
    return @{ Proc = $proc; Log = $log }
}

function Wait-CloudflaredUrl([string]$Log, [int]$maxSec = 120) {
    $regex = 'https://[a-z0-9-]+\.trycloudflare\.com'
    $deadline = (Get-Date).AddSeconds($maxSec)
    do {
        if (Test-Path $Log) {
            $text = Get-Content -Raw $Log
            if ($text -match $regex) { return $matches[0] }
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)
    return ""
}

# ===== LINE helpers =====
function Test-LineToken([string]$Tok) {
    try {
        $null = Invoke-RestMethod -Method Get -Uri "https://api.line.me/v2/bot/info" -Headers @{ Authorization = "Bearer $Tok" }
        return $true
    }
    catch { return $false }
}

function Set-LineWebhookEndpoint([string]$Tok, [string]$Url) {
    $body = @{ endpoint = $Url } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Put -Uri "https://api.line.me/v2/bot/channel/webhook/endpoint" -Headers @{ Authorization = "Bearer $Tok" } -ContentType "application/json" -Body $body | Out-Null
}

function Test-WebhookUntilOK([string]$Tok, [string]$Url) {
    $delays = @(3, 6, 10, 16, 24, 36, 60)
    foreach ($d in $delays) {
        Start-Sleep -Seconds $d
        try {
            $res = Invoke-RestMethod -Method Post -Uri "https://api.line.me/v2/bot/channel/webhook/test" -Headers @{ Authorization = "Bearer $Tok" } -ContentType "application/json" -Body (@{ endpoint = $Url } | ConvertTo-Json -Compress)
            if ($res.success) { return $true }
        }
        catch {}
    }
    return $false
}

# ===== Flow =====
if (-not (Test-Path ".\artisan")) { throw "artisan not found in $PSScriptRoot" }

$LineToken = Get-EnvNormalized $LineToken
$LineSecret = Get-EnvNormalized $LineSecret
Set-EnvSmart -Tok $LineToken -Sec $LineSecret

if ($AutoPickPort) { $Port = Get-FreePort -start $Port }

Write-Information "Starting Laravel dev server on http://$PhpHost`:$Port ..."
Start-Process -FilePath "php" -ArgumentList "artisan serve --host=$PhpHost --port=$Port" -WorkingDirectory $PSScriptRoot -NoNewWindow | Out-Null
[void](Wait-HttpReady "http://$PhpHost`:$Port" 60)

# cloudflared ensure + start
try {
    $cfExe = if ($CloudflaredPath) { $CloudflaredPath } else { Get-CloudflaredExe -Hint "" }
    if (-not(Test-Path $cfExe)) { throw "cloudflared exe not found: $cfExe" }
}
catch {
    throw "cloudflared install/resolve failed: $($_.Exception.Message)"
}

$cfInfo = Start-Cloudflared -CfExe $cfExe -LocalUrl ("http://{0}:{1}" -f $PhpHost, $Port)
$publicUrl = Wait-CloudflaredUrl -Log $cfInfo.Log -maxSec 120
if ([string]::IsNullOrWhiteSpace($publicUrl)) {
    Write-Warning "Public URL not ready. See log: $($cfInfo.Log)"
}
else {
    Write-Information "Public URL: $publicUrl"
}

# LINE webhook
$tok = if ($LineToken) { $LineToken } else { Get-DotenvValue "LINE_CHANNEL_ACCESS_TOKEN" }
if ($tok) {
    if (Test-LineToken -Tok $tok) {
        if ($publicUrl) {
            $webhook = "$publicUrl/api/line/webhook"
            Write-Information "Updating LINE Webhook -> $webhook"
            try {
                Set-LineWebhookEndpoint -Tok $tok -Url $webhook
                if (Test-WebhookUntilOK -Tok $tok -Url $webhook) {
                    Write-Information "LINE webhook test: success"
                }
                else {
                    Write-Warning "LINE webhook test did not return success yet."
                }
            }
            catch {
                Write-Warning "Failed to update/test LINE webhook: $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "No Public URL. Skipping webhook update."
        }
    }
    else {
        Write-Warning "LINE token invalid or cannot reach LINE API."
    }
}
else {
    Write-Warning "LINE token not found. Skipping webhook update."
}

# quick pings
try { $r = Invoke-WebRequest "http://$PhpHost`:$Port/api/nextplot/search?q=ping" -TimeoutSec 10; Write-Information "Local ping /api/nextplot/search -> $($r.StatusCode)" } catch {}
if ($publicUrl) {
    try { $r = Invoke-WebRequest "$publicUrl/api/nextplot/search?q=ping" -TimeoutSec 15; Write-Information "Public ping /api/nextplot/search -> $($r.StatusCode)" } catch {}
    try { $r = Invoke-WebRequest -Method Post "$publicUrl/api/line/webhook" -ContentType "application/json" -Body '{"events":[]}' -TimeoutSec 15; Write-Information "Public POST /api/line/webhook -> $($r.StatusCode)" } catch {}
}

# clipboard + open browser (best-effort)
try { if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { "$publicUrl/api/line/webhook" | Set-Clipboard; Write-Information "(Copied Webhook URL to clipboard)" } } catch {}
try { if ($publicUrl) { Start-Process "$publicUrl/api/nextplot/search?q=ping" | Out-Null } } catch {}

Write-Host ""
Write-Host "===== Summary ====="
Write-Host ("Local URL : http://{0}:{1}" -f $PhpHost, $Port)
$pubDisplay = if ([string]::IsNullOrWhiteSpace($publicUrl)) { "(not ready)" } else { $publicUrl }
Write-Host ("Public URL: {0}" -f $pubDisplay)
if (-not [string]::IsNullOrWhiteSpace($publicUrl)) { Write-Host ("Webhook   : {0}/api/line/webhook" -f $publicUrl) }
Write-Host ("cloudflared log: {0}" -f $cfInfo.Log)
Write-Host "==================="