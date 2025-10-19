[CmdletBinding()]
param(
    [string]$TargetDir = "C:\Tools\cloudflared",
    [switch]$AddToPathUser
)
$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function New-DirectoryIfMissing([string]$Path) { if (-not (Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null } }
function Add-UserPath([string]$Dir) {
    try {
        $cur = [Environment]::GetEnvironmentVariable("Path", "User"); if ($null -eq $cur) { $cur = "" }
        $parts = $cur.Split(';') | Where-Object { $_ -and $_.Trim() -ne "" }
        if ($parts -notcontains $Dir) { setx PATH (($parts + $Dir) -join ';') | Out-Null; Write-Host "Added to user PATH: $Dir" }
        else { Write-Host "User PATH already contains: $Dir" }
    }
    catch { Write-Warning "Failed to update user PATH: $($_.Exception.Message)" }
}
function Find-CloudflaredExisting() {
    $candidates = @(
        "C:\Tools\cloudflared\cloudflared.exe",
        "$env:ProgramFiles\Cloudflare\cloudflared\cloudflared.exe",
        "$env:ProgramFiles\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\cloudflared\cloudflared.exe",
        "$env:ProgramData\chocolatey\bin\cloudflared.exe",
        "C:\Windows\System32\cloudflared.exe"
    ); foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    $gc = Get-Command cloudflared -ErrorAction SilentlyContinue; if ($gc -and (Test-Path $gc.Source)) { return $gc.Source }
    foreach ($d in @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")) { $exe = Join-Path $d "cloudflared.exe"; if (Test-Path $exe) { return $exe } }
    return ""
}
function Get-CloudflaredLatest([string]$OutDir) {
    New-DirectoryIfMissing $OutDir
    $api = "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "PowerShell" }
    $asset = $rel.assets | Where-Object { $_.name -match 'cloudflared-windows-amd64\.exe$' } | Select-Object -First 1
    if (-not $asset) { throw "Could not find windows-amd64 .exe in latest release assets." }
    $dest = Join-Path $OutDir "cloudflared.exe"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $dest -UseBasicParsing
    return $dest
}
# Main
$found = Find-CloudflaredExisting
if ($found) {
    New-DirectoryIfMissing $TargetDir
    $dest = Join-Path $TargetDir "cloudflared.exe"
    if ((Resolve-Path $found).Path -ne (Resolve-Path $dest -ErrorAction SilentlyContinue)) { Copy-Item -Force $found $dest; Write-Host "Copied to: $dest" }
    $final = $dest
}
else {
    try {
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            Write-Host "Installing cloudflared via winget..."
            winget install --id Cloudflare.cloudflared -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            $gc2 = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($gc2 -and (Test-Path $gc2.Source)) { $final = $gc2.Source }
        }
    }
    catch { Write-Warning "winget install failed: $($_.Exception.Message)" }
    if (-not $final) { $final = Get-CloudflaredLatest -OutDir $TargetDir }
}
if (-not (Test-Path $final)) { throw "cloudflared exe not found after install. Aborting." }
try { & $final --version | Out-Null } catch { Write-Warning "cloudflared run test failed: $($_.Exception.Message)" }
if ($AddToPathUser) { Add-UserPath (Split-Path -Parent $final) }
$final