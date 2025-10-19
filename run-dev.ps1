Param(
  [int]$Port = 8000,
  [switch]$AutoPickPort,
  [string]$PhpHost = "127.0.0.1",
  [string]$CloudflaredPath = "",
  [string]$WebhookPath = "/api/line/webhook",
  [string]$LineToken = "",
  [string]$LineSecret = ""
)
# Wrapper to keep old command name working
$script = Join-Path $PSScriptRoot "dev-up.ps1"
if (-not (Test-Path $script)) { throw "dev-up.ps1 not found next to run-dev.ps1" }
& $script @PSBoundParameters