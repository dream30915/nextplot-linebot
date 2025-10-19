[CmdletBinding()]
param(
    [string]$Token = "",      # ถ้ามีใน .env แล้ว ไม่จำเป็น
    [string]$Secret = "",     # ถ้ามีใน .env แล้ว ไม่จำเป็น
    [int]$Port = 8000,
    [switch]$AutoPickPort
)
$ErrorActionPreference = "Stop"

# build command to run keepalive hidden on logon
$keep = Join-Path $PSScriptRoot "bot-keepalive.ps1"
if (-not (Test-Path $keep)) { throw "bot-keepalive.ps1 not found in $PSScriptRoot" }

$argParts = @()
if ($Token) { $argParts += ('-LineToken "{0}"' -f $Token) }
if ($Secret) { $argParts += ('-LineSecret "{0}"' -f $Secret) }
$argParts += ('-Port {0}' -f $Port)
if ($AutoPickPort) { $argParts += '-AutoPickPort' }
$argStr = ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" {1}' -f $keep, ($argParts -join ' ')).Trim()

$startupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$lnkPath = Join-Path $startupDir "NextplotLineBot.lnk"

$ws = New-Object -ComObject WScript.Shell
$lnk = $ws.CreateShortcut($lnkPath)
$lnk.TargetPath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe"
$lnk.Arguments = $argStr
$lnk.WorkingDirectory = $PSScriptRoot
$lnk.WindowStyle = 7 # Minimized
$lnk.IconLocation = "$env:SystemRoot\System32\shell32.dll,167"
$lnk.Save()

Write-Host "Startup shortcut installed: $lnkPath"
Write-Host "It will run bot-keepalive.ps1 hidden at next logon."