[CmdletBinding()]
Param(
    [switch]$DryRun,
    [switch]$Apply,
    [string]$DatabaseUrl
)
# Deploy Supabase schema.sql with optional dry-run (transaction rollback)
# Requirements: psql installed; SUPABASE_DB_URL env var or -DatabaseUrl provided

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# --- Helpers: .env loader and LINE push notifier ---
function Get-RepoRoot {
  try { return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path } catch { return (Join-Path $PSScriptRoot '..') }
}

function Read-DotEnv {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path -LiteralPath $Path)) { return $map }
  Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue |
    ForEach-Object {
      $line = $_.Trim()
      if (-not $line) { return }
      if ($line.StartsWith('#')) { return }
      if ($line -match '^[\s]*([A-Za-z0-9_]+)[\s]*=[\s]*(.*)$') {
        $k = $Matches[1].Trim()
        $v = $Matches[2].Trim()
        # Strip surrounding quotes if present
        if ((($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) -and $v.Length -ge 2) { $v = $v.Substring(1, $v.Length - 2) }
        $map[$k] = $v
      }
    }
  return $map
}

function Get-ConfigValue {
  param([string]$Name, [hashtable]$DotEnv)
  $val = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($val)) {
    if ($DotEnv.ContainsKey($Name)) { $val = [string]$DotEnv[$Name] }
  }
  return $val
}

function Get-DbHostFromUrl {
  param([string]$Url)
  try {
    $u = [Uri]$Url
    return $u.Host
  } catch {
    return ''
  }
}

function Send-LinePush {
  [CmdletBinding()] param(
    [Parameter(Mandatory=$true)][string]$AccessToken,
    [Parameter(Mandatory=$true)][string]$To,
    [Parameter(Mandatory=$true)][string]$Text
  )
  $headers = @{ Authorization = "Bearer $AccessToken"; 'Content-Type' = 'application/json' }
  $txt = if ($null -eq $Text) { 'Unknown error' } else { $Text }
  $payload = @{ to = $To; messages = @(@{ type = 'text'; text = ($txt.Substring(0, [Math]::Min(1200, $txt.Length))) }) }
  $json = $payload | ConvertTo-Json -Compress -Depth 5
  try {
    Invoke-RestMethod -Uri 'https://api.line.me/v2/bot/message/push' -Method Post -Headers $headers -Body $json -ErrorAction Stop | Out-Null
    return $true
  } catch {
    Write-Host "WARN: Failed to push LINE message to '$To': $($_.Exception.Message)" -ForegroundColor DarkYellow
    return $false
  }
}

function Notify-LineOnError {
  param(
    [string]$Mode,       # DryRun | Apply
    [string]$DbUrl,
    [string]$ErrorMessage,
    [hashtable]$DotEnv
  )
  $token = Get-ConfigValue -Name 'LINE_CHANNEL_ACCESS_TOKEN' -DotEnv $DotEnv
  if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Host 'INFO: Skipping LINE notify (LINE_CHANNEL_ACCESS_TOKEN missing).' -ForegroundColor DarkGray
    return
  }
  # Prefer owner list; fallback to allowlist
  $owner = Get-ConfigValue -Name 'NEXTPLOT_OWNER_LINE_USER_IDS' -DotEnv $DotEnv
  $recipientRaw = if (-not [string]::IsNullOrWhiteSpace($owner)) { $owner } else { Get-ConfigValue -Name 'LINE_USER_ID_ALLOWLIST' -DotEnv $DotEnv }
  if ([string]::IsNullOrWhiteSpace($recipientRaw)) {
    Write-Host 'INFO: Skipping LINE notify (no recipients in NEXTPLOT_OWNER_LINE_USER_IDS or LINE_USER_ID_ALLOWLIST).' -ForegroundColor DarkGray
    return
  }
  $ids = $recipientRaw -split '[,;\s]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
  if (-not $ids -or $ids.Count -eq 0) { return }

  $host = Get-DbHostFromUrl -Url $DbUrl
  $when = Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'
  $machine = $env:COMPUTERNAME
  $errText = if ($null -ne $ErrorMessage -and ($ErrorMessage.Trim()).Length -gt 0) { $ErrorMessage } else { 'Unknown error' }
  $firstLine = ($errText -split "(`r`n|`n)")[0]
  if (-not $firstLine) { $firstLine = 'Unknown error' }
  # Detailed message with quick tips
  $lines = @()
  $lines += "[NextPlot] Schema $Mode failed"
  if ($host) { $lines += "DB: $host" }
  $lines += "Time: $when"
  $lines += "Machine: $machine"
  $lines += '—'
  $lines += $firstLine
  $lines += '—'
  $lines += 'Tips:'
  $lines += '- ตรวจสอบ SUPABASE_DB_URL และ sslmode=require'
  $lines += '- ถ้าเครื่องคุณต่อ IPv6 ไม่ได้ ให้รันใน Supabase SQL Editor หรือ Cloud Shell'
  $lines += '- psql ต้องติดตั้งและอยู่ใน PATH'
  $lines += '- ถ้าเป็น duplicate/exists ให้รันสคริปต์ idempotent นี้ซ้ำได้อย่างปลอดภัย'
  $msg = ($lines -join "`n").Trim()

  foreach ($id in $ids) { [void](Send-LinePush -AccessToken $token -To $id -Text $msg) }
}

# Resolve DB URL
if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  $DatabaseUrl = $env:SUPABASE_DB_URL
}
if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  Write-Host "Database URL not provided. Please enter it now (or press Ctrl+C to cancel)." -ForegroundColor Yellow
  Write-Host "Format: postgresql://USER:PASSWORD@HOST:5432/DBNAME?sslmode=require" -ForegroundColor DarkYellow
  $DatabaseUrl = Read-Host -Prompt "SUPABASE_DB_URL"
}
if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  Write-Host "ERROR: Database URL was not provided." -ForegroundColor Red
  exit 2
}

# Load .env for notifications (optional)
$repoRoot = Get-RepoRoot
$dotEnvPath = Join-Path $repoRoot '.env'
$dotEnv = Read-DotEnv -Path $dotEnvPath

# Check psql availability
try {
  $psqlVersion = & psql --version
  Write-Host "Using $psqlVersion" -ForegroundColor Cyan
} catch {
  Write-Host "ERROR: psql not found in PATH." -ForegroundColor Red
  exit 3
}

# Locate schema file
$schemaPath = Join-Path $PSScriptRoot '..\supabase\schema.sql'
if (-not (Test-Path -LiteralPath $schemaPath)) {
  Write-Host "ERROR: Schema file not found: $schemaPath" -ForegroundColor Red
  exit 4
}

# Build psql command
$baseArgs = @('-v','ON_ERROR_STOP=1','-d', $DatabaseUrl)

if ($DryRun.IsPresent -and $Apply.IsPresent) {
  Write-Host "ERROR: Specify only one of -DryRun or -Apply." -ForegroundColor Red
  exit 5
}

if ($DryRun.IsPresent -or -not $Apply.IsPresent) {
  Write-Host "Starting dry-run (BEGIN ... ROLLBACK) of schema.sql" -ForegroundColor Yellow
  $tmpSql = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName() + '.sql')
  @(
    'BEGIN;'
    "\\i $schemaPath"
    'ROLLBACK;'
  ) | Out-File -LiteralPath $tmpSql -Encoding UTF8 -Force
  try {
    & psql @baseArgs -f $tmpSql
    Write-Host "Dry-run completed (no changes applied)." -ForegroundColor Green
    return
  } catch {
    $errMsg = $_.Exception.Message
    Write-Host "Dry-run FAILED: $errMsg" -ForegroundColor Red
    Notify-LineOnError -Mode 'DryRun' -DbUrl $DatabaseUrl -ErrorMessage $errMsg -DotEnv $dotEnv
    exit 10
  } finally {
    Remove-Item -LiteralPath $tmpSql -Force -ErrorAction SilentlyContinue
  }
}

if ($Apply.IsPresent) {
  Write-Host "Applying schema.sql (this will modify the database)" -ForegroundColor Yellow
  try {
    & psql @baseArgs -f $schemaPath
    Write-Host "Schema applied successfully." -ForegroundColor Green
  } catch {
    $errMsg = $_.Exception.Message
    Write-Host "Apply FAILED: $errMsg" -ForegroundColor Red
    Notify-LineOnError -Mode 'Apply' -DbUrl $DatabaseUrl -ErrorMessage $errMsg -DotEnv $dotEnv
    exit 11
  }
}
