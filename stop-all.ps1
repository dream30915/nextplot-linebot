$ErrorActionPreference = "SilentlyContinue"
Get-Process cloudflared -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process php -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Output "Stopped cloudflared and php artisan serve (if running)."