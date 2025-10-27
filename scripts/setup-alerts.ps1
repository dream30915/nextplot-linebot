param(
  [Parameter(Mandatory=$true)][string]$ProjectId,
  [string]$ServiceName = "nextplot-linebot",
  [string]$Region = "asia-southeast1",
  [string[]]$EmailAddresses
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

Write-Host "Setting up Cloud Run alerts for $ServiceName in $ProjectId/$Region" -ForegroundColor Cyan

function New-TempJson {
  param([string]$TemplatePath, [string]$ServiceName)
  if (-not (Test-Path -LiteralPath $TemplatePath)) {
    throw "Template not found: $TemplatePath"
  }
  $json = Get-Content -LiteralPath $TemplatePath -Raw -Encoding UTF8
  $json = $json -replace 'nextplot-linebot', [Regex]::Escape($ServiceName)
  $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName() + '.json')
  $json | Out-File -LiteralPath $tmp -Encoding UTF8
  return $tmp
}

# Optionally create email notification channels
$createdChannelIds = @()
if ($EmailAddresses -and $EmailAddresses.Count -gt 0) {
  foreach ($email in $EmailAddresses) {
    $email = $email.Trim()
    if ([string]::IsNullOrWhiteSpace($email)) { continue }
    $channelJson = @{
      type = 'email'
      displayName = "Ops Email: $email"
      description = "Alerts for $ServiceName"
      enabled = $true
      labels = @{ email_address = $email }
    } | ConvertTo-Json -Depth 5
    $tmpChannel = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName() + '.json')
    $channelJson | Out-File -LiteralPath $tmpChannel -Encoding UTF8
    Write-Host "Creating email notification channel: $email" -ForegroundColor Yellow
    $createOut = & gcloud alpha monitoring channels create --project $ProjectId --channel-content-from-file $tmpChannel 2>&1
    # Try to capture the created channel ID from output
    $id = ($createOut | Select-String -Pattern 'name: projects/.*/notificationChannels/(.*)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) | Select-Object -First 1
    if ($id) { $createdChannelIds += $id }
  }
}

# Create alert policies using templates (non-destructive to repo files)
$policy5xxTpl = Join-Path $PSScriptRoot "..\cloudrun-alerts\alert-policy-5xx.json"
$policyLatencyTpl = Join-Path $PSScriptRoot "..\cloudrun-alerts\alert-policy-latency.json"

$policyIds = @{}
if (Test-Path $policy5xxTpl) {
  $tmp = New-TempJson -TemplatePath $policy5xxTpl -ServiceName $ServiceName
  Write-Host "Creating 5xx rate alert policy…" -ForegroundColor Yellow
  $out = & gcloud alpha monitoring policies create --project $ProjectId --policy-from-file $tmp 2>&1
  $pid = ($out | Select-String -Pattern 'name: projects/.*/alertPolicies/(.*)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) | Select-Object -First 1
  if ($pid) { $policyIds['5xx'] = $pid }
}

if (Test-Path $policyLatencyTpl) {
  $tmp = New-TempJson -TemplatePath $policyLatencyTpl -ServiceName $ServiceName
  Write-Host "Creating latency (p95) alert policy…" -ForegroundColor Yellow
  $out = & gcloud alpha monitoring policies create --project $ProjectId --policy-from-file $tmp 2>&1
  $pid = ($out | Select-String -Pattern 'name: projects/.*/alertPolicies/(.*)' | ForEach-Object { $_.Matches[0].Groups[1].Value }) | Select-Object -First 1
  if ($pid) { $policyIds['latency'] = $pid }
}

# Attach notification channels if any created
if ($createdChannelIds.Count -gt 0 -and $policyIds.Keys.Count -gt 0) {
  foreach ($k in $policyIds.Keys) {
    $pid = $policyIds[$k]
    $joined = ($createdChannelIds | ForEach-Object { $_.Trim() }) -join ','
    Write-Host "Attaching channels to policy $k ($pid)…" -ForegroundColor Yellow
    & gcloud alpha monitoring policies update $pid --project $ProjectId --add-notification-channels $joined
  }
}

Write-Host "Alert policies setup complete." -ForegroundColor Green
