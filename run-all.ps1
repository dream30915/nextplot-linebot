[CmdletBinding()]
Param(
    # ใส่ค่าไว้ให้ครบ ใช้งานได้ทันที (แนะนำเปลี่ยนใหม่หลังทดสอบ)
    [string]$Token = "MzlxATDrbgU5D84zanluRvP/kgYSyIQZyA10SOtFENVzncFKGkBbkqXZ1oEqBWAgVn7rycxfaq7JMHAbRJGUxpG3aj74S/yhFiqi/fplP7YPADGs16gX1rCSPpYK1UAvP8xSWS7GfydFd2pN4ucr2wdB04t89/1O/w1cDnyilFU=",
    [string]$Secret = "7b61f77577cc663a7b62ba17051ef7ff",

    [int]$Port = 8000,
    [switch]$AutoPickPort,
    [string]$PhpHost = "127.0.0.1",

    # ปล่อยว่างไว้ได้ สคริปต์จะหา cloudflared เอง อัตโนมัติ
    [string]$CloudflaredPath = "",

    [string]$WebhookPath = "/api/line/webhook"
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# ===== Utils (รองรับ PS 5.1) =====
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
        else { $nl = [Environment]::NewLine; return ($Text.TrimEnd() + $nl + "$Key=""$escaped""") }
    }
}

function Get-DotenvValue([string]$Key) {
    if (-not(Test-Path ".\.env")) { return "" }
    $line = Select-String -Path .\.env -Pattern ("^\s*{0}\s*=" -f [regex]::Escape($Key)) | Select-Object -First 1
    if ($null -eq $line) { return "" }
    $val = ($line.Line -split '=', 2)[1]
    return $val.Trim().Trim('"').Trim("'")
}

function ShouldReplace([string]$v) {
    if ([string]::IsNullOrWhiteSpace($v)) { return $true }
    if ($v -match '^\s*<.+>\s*$') { return $true }
    if ($v -match '^\s*(PASTE_|YOUR_|TOKEN|SECRET)') { return $true }
    return $false
}

function Write-EnvSmart([string]$Tok, [string]$Sec) {
    $envFile = ".\.env"
    $content = ""
    if (Test-Path $envFile) { $content = [System.IO.File]::ReadAllText($envFile) }

    $curTok = Get-DotenvValue "LINE_CHANNEL_ACCESS_TOKEN"
    $curSec = Get-DotenvValue "LINE_CHANNEL_SECRET"

    if (ShouldReplace($curTok) -and -not [string]::IsNullOrWhiteSpace($Tok)) {
        $content = Set-DotenvKey -Text $content -Key "LINE_CHANNEL_ACCESS_TOKEN" -Value $Tok
    }
    if (ShouldReplace($curSec) -and -not [string]::IsNullOrWhiteSpace($Sec)) {
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
        if ($iar.AsyncWaitHandle.WaitOne(200) -and $c.Connected) { $c.EndConnect($iar); $c.Close(); return $true }
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
        catch { Start-Sleep -Milliseconds 800 }
    }while ((Get-Date) -lt $deadline)
    return $false
}

# ===== Services =====
function Start-PhpServe([string]$BindHost, [int]$P) {
    $serveArgs = "artisan serve --host=$BindHost --port=$P"
    Write-Information "Starting Laravel dev server on http://$BindHost`:$P ..."
    Start-Process -FilePath "php" -ArgumentList $serveArgs -WorkingDirectory $PSScriptRoot -NoNewWindow | Out-Null
}

function Resolve-CloudflaredPath([string]$hint) {
    $checked = @()

    function AddChecked([string]$p) { if ($p) { $script:checked += $p } }

    if (-not [string]::IsNullOrWhiteSpace($hint)) {
        AddChecked $hint
        if (Test-Path $hint) { return $hint }
    }

    $gc = (Get-Command cloudflared -ErrorAction SilentlyContinue)
    if ($gc) { AddChecked ("Get-Command -> " + $gc.Source); if (Test-Path $gc.Source) { return $gc.Source } }

    try {
        $w = (& where.exe cloudflared 2>$null | Select-Object -First 1)
        if ($w) { AddChecked ("where.exe -> " + $w); if (Test-Path $w) { return $w } }
    }
    catch {}

    $candidates = @(
        "C:\Program Files\Cloudflare\cloudflared\cloudflared.exe",
        "C:\Program Files\cloudflared\cloudflared.exe",
        "C:\Program Files (x86)\Cloudflare\cloudflared\cloudflared.exe",
        "$env:ProgramFiles\Cloudflare\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\cloudflared\cloudflared.exe",
        "$env:USERPROFILE\cloudflared.exe",
        "$env:USERPROFILE\cloudflared\cloudflared.exe",
        "$env:ProgramData\chocolatey\bin\cloudflared.exe",
        "C:\Windows\System32\cloudflared.exe"
    )
    foreach ($p in $candidates) {
        AddChecked $p
        if ($p -and (Test-Path $p)) { return $p }
    }

    # ค้นจาก Registry Uninstall -> InstallLocation
    $regRoots = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"
    )
    foreach ($root in $regRoots) {
        try {
            $keys = Get-ChildItem $root -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                try {
                    $dn = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).DisplayName
                    $il = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).InstallLocation
                    if ($dn -and ($dn -match "cloudflared") -and $il) {
                        $guess = Join-Path $il "cloudflared.exe"
                        AddChecked ("registry -> " + $guess)
                        if (Test-Path $guess) { return $guess }
                    }
                }
                catch {}
            }
        }
        catch {}
    }

    # ติดตั้งด้วย winget ถ้าเจอ winget
    $winget = (Get-Command winget -ErrorAction SilentlyContinue)
    if ($winget) {
        Write-Information "cloudflared not found. Installing via winget..."
        Start-Process -FilePath $winget.Source -ArgumentList 'install --id Cloudflare.cloudflared -e --silent --accept-package-agreements --accept-source-agreements' -Wait -NoNewWindow | Out-Null

        # ตรวจซ้ำทันที
        $gc2 = (Get-Command cloudflared -ErrorAction SilentlyContinue)
        if ($gc2 -and (Test-Path $gc2.Source)) { return $gc2.Source }

        $postInstall = @(
            "C:\Program Files\Cloudflare\cloudflared\cloudflared.exe",
            "C:\Program Files\cloudflared\cloudflared.exe"
        )
        foreach ($p in $postInstall) {
            AddChecked ("post-install -> " + $p)
            if (Test-Path $p) { return $p }
        }
    }

    $msg = "cloudflared not found. Checked:`n" + ($checked -join "`n")
    throw $msg
}

function Start-Cloudflared([string]$CfExe, [string]$LocalUrl) {
    if (-not(Test-Path $CfExe)) { throw "cloudflared not found at $CfExe" }
    $log = Join-Path $env:TEMP ("cloudflared-" + (Get-Date -Format "yyyyMMddHHmmss") + ".log")
    $arguments = @(
        "tunnel",
        "--ha-connections", "2",
        "--no-autoupdate",
        "--url", $LocalUrl,
        "--logfile", $log,
        "--metrics", "127.0.0.1:0"
    )
    Write-Information "Starting cloudflared quick tunnel for $LocalUrl ..."
    $proc = Start-Process -FilePath $CfExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
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
    }while ((Get-Date) -lt $deadline)
    return ""
}

# ===== LINE =====
function Test-LineToken([string]$Tok) {
    try {
        $null = Invoke-RestMethod -Method Get -Uri "https://api.line.me/v2/bot/info" -Headers @{ Authorization = "Bearer $Tok" }
        Write-Information "LINE token OK (bot info received)."
        return $true
    }
    catch {
        Write-Warning ("LINE token check failed: " + $_.Exception.Message)
        return $false
    }
}

function Set-LineWebhookEndpoint([string]$Tok, [string]$Url) {
    $body = @{ endpoint = $Url } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Put -Uri "https://api.line.me/v2/bot/channel/webhook/endpoint" -Headers @{ Authorization = "Bearer $Tok" } -ContentType "application/json" -Body $body | Out-Null
}

function Test-WebhookUntilOK([string]$Tok, [string]$Url) {
    $delays = @(3, 6, 10, 16, 24, 36, 60)
    foreach ($d in $delays) {
        Write-Information "Testing LINE Webhook endpoint (wait $d s) ..."
        Start-Sleep -Seconds $d
        try {
            $res = Invoke-RestMethod -Method Post -Uri "https://api.line.me/v2/bot/channel/webhook/test" -Headers @{ Authorization = "Bearer $Tok" } -ContentType "application/json" -Body (@{ endpoint = $Url } | ConvertTo-Json -Compress)
            Write-Information ("LINE test result: " + ($res | ConvertTo-Json -Compress))
            if ($res.success) { return $true }
        }
        catch {
            Write-Warning ("LINE webhook test failed: " + $_.Exception.Message)
        }
    }
    return $false
}

# ===== Flow =====
if (-not (Test-Path ".\artisan")) { throw "artisan not found in $PSScriptRoot" }

$Token = Get-EnvNormalized $Token
$Secret = Get-EnvNormalized $Secret
Write-EnvSmart -Tok $Token -Sec $Secret
if ([string]::IsNullOrWhiteSpace($Token)) { $Token = Get-DotenvValue "LINE_CHANNEL_ACCESS_TOKEN" }

if ($AutoPickPort) { $Port = Get-FreePort -start $Port }

$null = Start-PhpServe -BindHost $PhpHost -P $Port
[void](Wait-HttpReady "http://$PhpHost`:$Port" 60)

$cfExe = Resolve-CloudflaredPath -hint $CloudflaredPath
$cfInfo = Start-Cloudflared -CfExe $cfExe -LocalUrl ("http://{0}:{1}" -f $PhpHost, $Port)
$publicUrl = Wait-CloudflaredUrl -Log $cfInfo.Log -maxSec 120
if ([string]::IsNullOrWhiteSpace($publicUrl)) {
    Write-Warning "Public URL not reachable yet; will continue anyway."
    Write-Information ("cloudflared log: " + $cfInfo.Log)
}
else {
    Write-Information "Public URL: $publicUrl"
}
$webhook = if ([string]::IsNullOrWhiteSpace($publicUrl)) { "" } else { "$publicUrl$WebhookPath" }

try { if (-not [string]::IsNullOrWhiteSpace($publicUrl)) { [void](Wait-HttpReady "$publicUrl/api/nextplot/search?q=ping" 60) } }catch {}

if (-not [string]::IsNullOrWhiteSpace($Token)) {
    if (Test-LineToken -Tok $Token) {
        if (-not [string]::IsNullOrWhiteSpace($webhook)) {
            Write-Information "Updating LINE Webhook endpoint to $webhook ..."
            Set-LineWebhookEndpoint -Tok $Token -Url $webhook
            [void](Test-WebhookUntilOK -Tok $Token -Url $webhook)
        }
        else {
            Write-Warning "Skip webhook update: public URL not found."
        }
    }
}
else {
    Write-Warning "LINE token not found. Skipping webhook update/verify."
}

if (-not [string]::IsNullOrWhiteSpace($publicUrl)) {
    try { $r = Invoke-WebRequest "$publicUrl/api/nextplot/search?q=ping" -TimeoutSec 15; Write-Information "HTTP: GET /api/nextplot/search ... $($r.StatusCode)" }catch { Write-Warning "HTTP: GET /api/nextplot/search ... FAILED ($($_.Exception.Message))" }
    if (-not [string]::IsNullOrWhiteSpace($webhook)) {
        try { $r = Invoke-WebRequest -Method Post "$webhook" -ContentType "application/json" -Body '{"events":[]}' -TimeoutSec 15; Write-Information "HTTP: POST /api/line/webhook ... $($r.StatusCode)" }catch { Write-Warning "HTTP: POST /api/line/webhook ... FAILED ($($_.Exception.Message))" }
    }
    try { if (Get-Command Set-Clipboard -ErrorAction SilentlyContinue) { $webhook | Set-Clipboard; Write-Information "(Copied Webhook URL to clipboard)" } }catch {}
    try { if (-not [string]::IsNullOrWhiteSpace($publicUrl)) { Start-Process "$publicUrl/api/nextplot/search?q=ping" | Out-Null } }catch {}
}

Write-Information "Done. Use .\stop-all.ps1 to stop."