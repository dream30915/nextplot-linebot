[CmdletBinding()]
param(
    [string]$LineToken = "",
    [string]$LineSecret = "",
    [int]$Port = 8000,
    [switch]$AutoPickPort,
    [string]$PhpHost = "127.0.0.1",
    [int]$CheckIntervalSec = 20,
    [string]$CloudflaredPath = ""
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function New-RunDir() { $dir = Join-Path $PSScriptRoot ".run"; if (-not(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }; return $dir }
function Read-Env([string]$key) {
    if (-not(Test-Path ".\.env")) { return "" }
    $m = Select-String -Path .\.env -Pattern ("^\s*{0}\s*=" -f [regex]::Escape($key)) | Select-Object -First 1
    if ($null -eq $m) { return "" }
    (($m.Line -split '=', 2)[1]).Trim().Trim('"').Trim("'")
}
function Set-Env([hashtable]$pairs) {
    $f = ".\.env"; $txt = if (Test-Path $f) { [IO.File]::ReadAllText($f) } else { "" }
    foreach ($k in $pairs.Keys) {
        $v = [string]$pairs[$k]; $v2 = $v -replace '"', '\"'
        $pat = "^{0}\s*=.*$" -f [regex]::Escape($k)
        if ([regex]::IsMatch($txt, $pat, 'Multiline')) { $txt = [regex]::Replace($txt, $pat, ("$k=""{0}""" -f $v2), 'Multiline') }
        else { if ([string]::IsNullOrWhiteSpace($txt)) { $txt = "$k=""$v2""" } else { $nl = [Environment]::NewLine; $txt = $txt.TrimEnd() + $nl + "$k=""$v2""" } }
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false); [IO.File]::WriteAllText($f, $txt, $utf8)
}
function Test-Port([int]$p) { try { $c = New-Object System.Net.Sockets.TcpClient; $iar = $c.BeginConnect("127.0.0.1", $p, $null, $null); if ($iar.AsyncWaitHandle.WaitOne(150) -and $c.Connected) { $c.EndConnect($iar); $c.Close(); return $true }; $c.Close(); return $false }catch { return $false } }
function Get-FreePort([int]$start) { $p = $start; for ($i = 0; $i -lt 200; $i++) { if (-not(Test-Port $p)) { return $p }; $p++ }; throw "No free port" }
function Wait-Http([string]$url, [int]$max = 60) { $dl = (Get-Date).AddSeconds($max); do { try { Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 | Out-Null; return $true }catch { Start-Sleep -Milliseconds 700 } }while ((Get-Date) -lt $dl); return $false }
function Get-CloudflaredExe([string]$hint) {
    if ($hint -and (Test-Path $hint)) { return $hint }
    $cand = @("C:\Tools\cloudflared\cloudflared.exe", "$env:ProgramFiles\Cloudflare\cloudflared\cloudflared.exe", "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe", "$env:LOCALAPPDATA\cloudflared\cloudflared.exe", "$env:ProgramData\chocolatey\bin\cloudflared.exe", "C:\Windows\System32\cloudflared.exe")
    foreach ($p in $cand) { if (Test-Path $p) { return $p } }
    $gc = Get-Command cloudflared -ErrorAction SilentlyContinue; if ($gc -and (Test-Path $gc.Source)) { return $gc.Source }
    $installer = Join-Path $PSScriptRoot "tools\install-cloudflared.ps1"
    if (-not(Test-Path $installer)) { throw "tools\install-cloudflared.ps1 not found." }
    $final = & $installer -TargetDir "C:\Tools\cloudflared" -AddToPathUser
    if (-not(Test-Path $final)) { throw "cloudflared not found after install: $final" }
    return $final
}
function Start-Laravel([int]$port, [string]$bindHost) {
    $run = New-RunDir; $pidFile = Join-Path $run "laravel.pid"
    if (Test-Path $pidFile) { try { $old = [int](Get-Content $pidFile); $p = Get-Process -Id $old -ErrorAction Stop; if ($p) { return $old } }catch {} }
    $proc = Start-Process -FilePath "php" -ArgumentList "artisan serve --host=$bindHost --port=$port" -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -PassThru
    $proc.Id | Out-File $pidFile -Encoding ascii -Force
    return $proc.Id
}
function Start-CloudflaredProc([string]$cfExe, [string]$localUrl) {
    $run = New-RunDir; $pidFile = Join-Path $run "cloudflared.pid"; $log = Join-Path $run ("cloudflared-" + (Get-Date -Format "yyyyMMddHHmmss") + ".log")
    $cfArgs = @("tunnel", "--ha-connections", "2", "--no-autoupdate", "--url", $localUrl, "--logfile", $log, "--metrics", "127.0.0.1:0")
    $proc = Start-Process -FilePath $cfExe -ArgumentList $cfArgs -WindowStyle Hidden -PassThru
    $proc.Id | Out-File $pidFile -Encoding ascii -Force
    return @{ Pid = $proc.Id; Log = $log }
}
function Get-CloudflaredUrl([string]$log, [int]$max = 120) {
    $rx = 'https://[a-z0-9-]+\.trycloudflare\.com'
    $dl = (Get-Date).AddSeconds($max)
    do { if (Test-Path $log) { $t = Get-Content -Raw $log; if ($t -match $rx) { return $matches[0] } }; Start-Sleep -Milliseconds 500 }while ((Get-Date) -lt $dl)
    return ""
}
function Stop-ByPidFile([string]$file) {
    if (Test-Path $file) {
        try {
            $targetPid = [int](Get-Content $file)
            Stop-Process -Id $targetPid -Force -ErrorAction SilentlyContinue
        }
        catch {}
        Remove-Item -Force $file -ErrorAction SilentlyContinue
    }
}
function Test-LineToken([string]$tok) { try { Invoke-RestMethod -Method Get "https://api.line.me/v2/bot/info" -Headers @{ Authorization = "Bearer $tok" } | Out-Null; return $true }catch { return $false } }
function Set-LineWebhook([string]$tok, [string]$url) { $b = @{endpoint = $url } | ConvertTo-Json -Compress; Invoke-RestMethod -Method Put "https://api.line.me/v2/bot/channel/webhook/endpoint" -Headers @{ Authorization = "Bearer $tok" } -ContentType "application/json" -Body $b | Out-Null }
function Test-LineWebhook([string]$tok, [string]$url) { $b = @{endpoint = $url } | ConvertTo-Json -Compress; try { $r = Invoke-RestMethod -Method Post "https://api.line.me/v2/bot/channel/webhook/test" -Headers @{ Authorization = "Bearer $tok" } -ContentType "application/json" -Body $b; return ($r.success -eq $true) }catch { return $false } }

# Bootstrap
if (-not(Test-Path ".\.env") -and (Test-Path ".\.env.example")) { Copy-Item .\.env.example .\.env }
if ([string]::IsNullOrWhiteSpace($LineToken)) { $LineToken = Read-Env "LINE_CHANNEL_ACCESS_TOKEN" }
if ([string]::IsNullOrWhiteSpace($LineSecret)) { $LineSecret = Read-Env "LINE_CHANNEL_SECRET" }
Set-Env @{ "LINE_CHANNEL_ACCESS_TOKEN" = $LineToken; "LINE_CHANNEL_SECRET" = $LineSecret; "LINE_SIGNATURE_RELAXED" = "true"; "APP_DEBUG" = "true" }

if ($AutoPickPort) { $Port = Get-FreePort -start $Port }
$null = Start-Laravel -port $Port -bindHost $PhpHost
[void](Wait-Http ("http://{0}:{1}" -f $PhpHost, $Port) 60)

$cfExe = Get-CloudflaredExe -hint $CloudflaredPath
$cfInfo = Start-CloudflaredProc -cfExe $cfExe -localUrl ("http://{0}:{1}" -f $PhpHost, $Port)
$publicUrl = Get-CloudflaredUrl -log $cfInfo.Log -max 120

if ($publicUrl) { Write-Host ("Public URL: {0}" -f $publicUrl) } else { Write-Warning ("Public URL not ready. Log: {0}" -f $cfInfo.Log) }

$tokenOk = $false
if (-not [string]::IsNullOrWhiteSpace($LineToken)) { $tokenOk = Test-LineToken -tok $LineToken }

if ($tokenOk -and $publicUrl) {
    $wb = "$publicUrl/api/line/webhook"
    try { Set-LineWebhook -tok $LineToken -url $wb; if (Test-LineWebhook -tok $LineToken -url $wb) { Write-Host "LINE webhook set & verified." } else { Write-Warning "Webhook set but test not yet success." } }catch { Write-Warning "Set webhook failed: $($_.Exception.Message)" }
}
else {
    if (-not $tokenOk) { Write-Warning "LINE token invalid or cannot reach LINE API; webhook auto-update skipped." }
}

$run = New-RunDir
$stateFile = Join-Path $run "state.json"
if ($publicUrl) { @{ publicUrl = $publicUrl; ts = (Get-Date) } | ConvertTo-Json | Out-File $stateFile -Encoding UTF8 }

$failCount = 0
while ($true) {
    Start-Sleep -Seconds $CheckIntervalSec

    try {
        if (-not (Wait-Http ("http://{0}:{1}/api/nextplot/search?q=ping" -f $PhpHost, $Port) 5)) {
            Stop-ByPidFile (Join-Path $run "laravel.pid")
            $null = Start-Laravel -port $Port -bindHost $PhpHost
        }
    }
    catch {}

    $urlNow = $publicUrl
    $needRestart = $false
    try {
        if ([string]::IsNullOrWhiteSpace($urlNow)) { $needRestart = $true }
        else {
            try {
                Invoke-WebRequest "$urlNow/api/nextplot/search?q=ping" -TimeoutSec 8 | Out-Null
                $failCount = 0
            }
            catch {
                $failCount++
                if ($failCount -ge 3) { $needRestart = $true; $failCount = 0 }
            }
        }
    }
    catch { $needRestart = $true }

    if ($needRestart) {
        Stop-ByPidFile (Join-Path $run "cloudflared.pid")
        $cfInfo = Start-CloudflaredProc -cfExe $cfExe -localUrl ("http://{0}:{1}" -f $PhpHost, $Port)
        $newUrl = Get-CloudflaredUrl -log $cfInfo.Log -max 120
        if (-not [string]::IsNullOrWhiteSpace($newUrl) -and $newUrl -ne $publicUrl) {
            $publicUrl = $newUrl
            @{ publicUrl = $publicUrl; ts = (Get-Date) } | ConvertTo-Json | Out-File $stateFile -Encoding UTF8
            Write-Host ("New Public URL: {0}" -f $publicUrl)
            if ($tokenOk) {
                $wb = "$publicUrl/api/line/webhook"
                try { Set-LineWebhook -tok $LineToken -url $wb; [void](Test-LineWebhook -tok $LineToken -url $wb); Write-Host "Webhook updated to new URL." }catch { Write-Warning "Webhook update failed: $($_.Exception.Message)" }
            }
        }
    }
}