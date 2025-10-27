param(
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$ServiceName = "nextplot-linebot",
  [string]$Region = "asia-southeast1"
)

Write-Host "Setting up example Cloud Run alerts for $ServiceName in $ProjectId/$Region" -ForegroundColor Cyan

# NOTE: Adjust JSON templates as needed before running. This script demonstrates the commands.
# 1) 5xx rate alert (uses run.googleapis.com/request_count with 5xx filter)
$policy5xx = Join-Path $PSScriptRoot "..\cloudrun-alerts\alert-policy-5xx.json"
if (Test-Path $policy5xx) {
  (Get-Content $policy5xx -Raw) | ForEach-Object { $_ -replace 'nextplot-linebot', $ServiceName } | Set-Content $policy5xx
  & gcloud alpha monitoring policies create --project $ProjectId --policy-from-file $policy5xx
}

# 2) latency alert (p95)
$policyLatency = Join-Path $PSScriptRoot "..\cloudrun-alerts\alert-policy-latency.json"
if (Test-Path $policyLatency) {
  (Get-Content $policyLatency -Raw) | ForEach-Object { $_ -replace 'nextplot-linebot', $ServiceName } | Set-Content $policyLatency
  & gcloud alpha monitoring policies create --project $ProjectId --policy-from-file $policyLatency
}

Write-Host "Done. Configure notification channels in Cloud Monitoring and attach to these policies." -ForegroundColor Green
