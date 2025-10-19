[CmdletBinding()]
param(
    [string]$TargetDir = "C:\Tools\cloudflared",
    [switch]$AddToPathUser
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Ensure-Dir([string]$p) {
    if (-not(Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
}

function Add-PathUser([string]$dir) {
    try {
        $cur = [Environment]::GetEnvironmentVariable("Path", "User")
        if ($null -eq $cur) { $cur = "" }
        $parts = $cur.Split(';') | Where-Object { $_ -and $_.Trim() -ne "" }
        if ($parts -notcontains $dir) {
            $new = ($parts + $dir) -join ';'
            setx PATH $new | Out-Null
            Write-Host "Added to user PATH: $dir"
        }
        else {
            Write-Host "User PATH already contains: $dir"
        }
    }
    catch {
        Write-Warning "Failed to update user PATH: $($_.Exception.Message)"
    }
}

function Find-ExistingCloudflared() {
    $candidates = @()
    $add = { param($p) if ($p -and (Test-Path $p)) { $script:candidates += $p } }

    & $add "C:\Tools\cloudflared\cloudflared.exe"
    $gc = (Get-Command cloudflared -ErrorAction SilentlyContinue)
    if ($gc -and (Test-Path $gc.Source)) { & $add $gc.Source }

    $popular = @(
        "$env:ProgramFiles\Cloudflare\cloudflared\cloudflared.exe",
        "$env:ProgramFiles\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\Programs\cloudflared\cloudflared.exe",
        "$env:LOCALAPPDATA\cloudflared\cloudflared.exe",
        "$env:ProgramData\chocolatey\bin\cloudflared.exe",
        "C:\Windows\System32\cloudflared.exe"
    )
    foreach ($p in $popular) { & $add $p }

    # Also check common download folders quickly (non-recursive deep scan)
    $dl = @("$env:USERPROFILE\Downloads", "$env:USERPROFILE\Desktop")
    foreach ($d in $dl) {
        $exe = Join-Path $d "cloudflared.exe"
        & $add $exe
    }

    return $candidates | Select-Object -First 1
}

function Download-Latest() {
    $api = "https://api.github.com/repos/cloudflare/cloudflared/releases/latest"
    Write-Host "Querying latest release: $api"
    $rel = Invoke-RestMethod -Uri $api -Headers @{ "User-Agent" = "PowerShell" }
    $asset = $rel.assets | Where-Object { $_.name -match 'cloudflared-windows-amd64\.exe$' } | Select-Object -First 1
    if (-not $asset) {
        throw "Could not find windows-amd64 .exe in the latest release assets."
    }
    $url = $asset.browser_download_url
    Write-Host "Downloading: $url"
    Ensure-Dir $TargetDir
    $dest = Join-Path $TargetDir "cloudflared.exe"
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    return $dest
}

# Main
$found = Find-ExistingCloudflared
if ($found) {
    Write-Host "Found existing cloudflared: $found"
    Ensure-Dir $TargetDir
    $dest = Join-Path $TargetDir "cloudflared.exe"
    if ((Resolve-Path $found).Path -ne (Resolve-Path $dest -ErrorAction SilentlyContinue)) {
        Copy-Item -Force $found $dest
        Write-Host "Copied to: $dest"
    }
    $final = $dest
}
else {
    try {
        # Try winget first if available
        $wg = Get-Command winget -ErrorAction SilentlyContinue
        if ($wg) {
            Write-Host "Installing cloudflared via winget..."
            winget install --id Cloudflare.cloudflared -e --silent --accept-package-agreements --accept-source-agreements | Out-Null
            $gc2 = Get-Command cloudflared -ErrorAction SilentlyContinue
            if ($gc2 -and (Test-Path $gc2.Source)) {
                $final = $gc2.Source
            }
        }
    }
    catch {
        Write-Warning "winget install failed: $($_.Exception.Message)"
    }

    if (-not $final) {
        $final = Download-Latest
    }
}

if (-not(Test-Path $final)) { throw "cloudflared exe not found after install. Aborting." }
Write-Host "cloudflared ready at: $final"

try {
    & $final --version
}
catch {
    Write-Warning "cloudflared run test failed: $($_.Exception.Message)"
}

if ($AddToPathUser) { Add-PathUser (Split-Path -Parent $final) }

# Output path for caller scripts
$final