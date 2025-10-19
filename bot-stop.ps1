[CmdletBinding()]
param()
$ErrorActionPreference = "SilentlyContinue"
$run = Join-Path $PSScriptRoot ".run"
Get-ChildItem $run -Filter "*.pid" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $pidLocal = [int](Get-Content $_.FullName)
        Stop-Process -Id $pidLocal -Force -ErrorAction SilentlyContinue
    }
    catch {}
}
Remove-Item -Force -Recurse $run -ErrorAction SilentlyContinue
Write-Host "Stopped php artisan serve and cloudflared (if started by the keepalive script)."