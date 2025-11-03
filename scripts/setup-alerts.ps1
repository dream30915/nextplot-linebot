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
  # Use literal replacement to avoid escaping characters into JSON/MQL filters
  $json = $json.Replace('nextplot-linebot', $ServiceName)
  $tmp = [IO.Path]::Combine([IO.Path]::GetTempPath(), [IO.Path]::GetRandomFileName() + '.json')
  $json | Out-File -LiteralPath $tmp -Encoding UTF8
  return $tmp
}

# Get an OAuth access token using gcloud
function Get-AccessToken {
  $tok = & gcloud auth print-access-token 2>&1
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($tok)) {
    throw "Failed to obtain access token. Ensure 'gcloud auth login' completed."
  }
  return $tok.Trim()
}

# Create an alert policy via REST (works even if alpha CLI is unavailable)
function New-AlertPolicyFromFile {
  param(
    [string]$ProjectId,
    [string]$JsonPath,
    [string[]]$ChannelIds
  )
  if (-not (Test-Path -LiteralPath $JsonPath)) { throw "Policy JSON not found: $JsonPath" }
  $obj = Get-Content -LiteralPath $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -eq $obj) { throw "Invalid policy JSON in: $JsonPath" }
  if ($ChannelIds -and $ChannelIds.Count -gt 0) {
    $obj.notificationChannels = @()
    foreach ($cid in $ChannelIds) { $obj.notificationChannels += "projects/$ProjectId/notificationChannels/$cid" }
  }
  $body = $obj | ConvertTo-Json -Depth 20
  $token = Get-AccessToken
  $uri = "https://monitoring.googleapis.com/v3/projects/$ProjectId/alertPolicies"
  try {
    $resp = Invoke-RestMethod -Method Post -Uri $uri -Headers @{Authorization = "Bearer $token"} -ContentType 'application/json' -Body $body
    $name = $resp.name
    $policyId = if ($name) { ($name -split '/')[-1] } else { '' }
    return @{ id = $policyId; name = $name }
  } catch {
    Write-Host "Policy create failed for $JsonPath" -ForegroundColor Red
    Write-Host ($_.Exception.Message) -ForegroundColor Red
    $respProp = $null
    try { $respProp = $_.Exception.Response } catch { $respProp = $null }
    if ($respProp) {
      $reader = New-Object System.IO.StreamReader($respProp.GetResponseStream())
      $errBody = $reader.ReadToEnd()
      Write-Host $errBody -ForegroundColor Red
    } else {
      $_ | Out-String | Write-Host
    }
    throw
  }
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
  $createOut = & gcloud monitoring channels create --project $ProjectId --channel-content-from-file $tmpChannel 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to create notification channel for $email" -ForegroundColor Red
    $createOut | Out-String | Write-Host
  }
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
  $res = New-AlertPolicyFromFile -ProjectId $ProjectId -JsonPath $tmp -ChannelIds $createdChannelIds
  if ($res.id) { $policyIds['5xx'] = $res.id; Write-Host "Created policy: $($res.name)" -ForegroundColor Green }
}

if (Test-Path $policyLatencyTpl) {
  $tmp = New-TempJson -TemplatePath $policyLatencyTpl -ServiceName $ServiceName
  Write-Host "Creating latency (p95) alert policy…" -ForegroundColor Yellow
  $res = New-AlertPolicyFromFile -ProjectId $ProjectId -JsonPath $tmp -ChannelIds $createdChannelIds
  if ($res.id) { $policyIds['latency'] = $res.id; Write-Host "Created policy: $($res.name)" -ForegroundColor Green }
}

# No separate attachment step needed; channels were embedded during creation

Write-Host "Alert policies setup complete." -ForegroundColor Green
