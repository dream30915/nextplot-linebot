[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$startupDir = [Environment]::GetFolderPath([Environment+SpecialFolder]::Startup)
$lnkPath = Join-Path $startupDir "NextplotLineBot.lnk"
if (Test-Path $lnkPath) {
    Remove-Item -Force $lnkPath
    Write-Host "Removed startup shortcut: $lnkPath"
}
else {
    Write-Host "Startup shortcut not found: $lnkPath"
}