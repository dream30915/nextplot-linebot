# ปิด cloudflared และ php artisan serve
$ErrorActionPreference = "SilentlyContinue"
Stop-Process -Name cloudflared -Force
Get-Process -Name php | Where-Object { $_.Path -like "*php.exe" } | Stop-Process -Force
Write-Host "Stopped cloudflared and php artisan serve (if running)."