<#
.SYNOPSIS
  Send a LINE webhook request with a correctly signed X-Line-Signature header.

.DESCRIPTION
  Computes Base64(HMAC-SHA256(secret, rawBody)) and POSTs the body to the given URL.
  Supports providing the secret via a SecureString parameter, environment variable, or plain string.

.PARAMETER Url
  The webhook endpoint URL (e.g., https://<cloud-run-url>/api/line/webhook).

.PARAMETER SecretSecure
  The LINE Channel secret as a SecureString. Prefer this for interactive use.

.PARAMETER SecretEnvVar
  Name of an environment variable that contains the LINE Channel secret (e.g., STAGING_LINE_CHANNEL_SECRET).

.PARAMETER Secret
  The LINE Channel secret as plain text. Use only in non-interactive environments where necessary.

.PARAMETER BodyJson
  The JSON body to send. Defaults to '{"events":[]}'.

.PARAMETER BodyFile
  Path to a file containing the JSON body. If provided, supersedes -BodyJson.

.PARAMETER OutFile
  Path to write the response body.

.EXAMPLE
  # Prompt for secret securely and send a minimal payload
  $sec = Read-Host -AsSecureString 'Enter LINE Channel Secret'
  ./scripts/send-signed-webhook.ps1 -Url 'https://<url>/api/line/webhook' -SecretSecure $sec -BodyJson '{"events":[]}'

.EXAMPLE
  # Use env var for secret (recommended for CI)
  $env:STAGING_LINE_CHANNEL_SECRET = '<secret>'
  ./scripts/send-signed-webhook.ps1 -Url 'https://<url>/api/line/webhook' -SecretEnvVar STAGING_LINE_CHANNEL_SECRET -BodyFile './payloads/webhook.json'

.NOTES
  - Never commit secrets. Prefer SecretSecure or environment variables.
  - Ensure the body used for signature is EXACTLY the body sent.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, HelpMessage = 'Webhook URL, e.g., https://<url>/api/line/webhook')]
  [ValidateNotNullOrEmpty()]
  [string]$Url,

  [Parameter(Mandatory = $false)]
  [SecureString]$SecretSecure,

  [Parameter(Mandatory = $false)]
  [string]$SecretEnvVar,

  [Parameter(Mandatory = $false)]
  [string]$Secret,

  [Parameter(Mandatory = $false)]
  [string]$BodyJson = '{"events":[]}',

  [Parameter(Mandatory = $false)]
  [string]$BodyFile,

  [Parameter(Mandatory = $false)]
  [string]$OutFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function ConvertFrom-SecureStringPlain {
  param([SecureString]$Secure)
  if (-not $Secure) { return $null }
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) } }
}

# Resolve secret
$secretPlain = $null
if ($PSBoundParameters.ContainsKey('SecretSecure') -and $SecretSecure) {
  $secretPlain = ConvertFrom-SecureStringPlain -Secure $SecretSecure
} elseif ($PSBoundParameters.ContainsKey('SecretEnvVar') -and $SecretEnvVar) {
  $secretPlain = [Environment]::GetEnvironmentVariable($SecretEnvVar)
} elseif ($PSBoundParameters.ContainsKey('Secret') -and $Secret) {
  $secretPlain = $Secret
}

if ([string]::IsNullOrEmpty($secretPlain)) {
  throw 'Missing secret: provide -SecretSecure, -SecretEnvVar, or -Secret.'
}

# Resolve body
if ($PSBoundParameters.ContainsKey('BodyFile') -and $BodyFile) {
  if (-not (Test-Path -LiteralPath $BodyFile)) { throw "Body file not found: $BodyFile" }
  $BodyJson = Get-Content -LiteralPath $BodyFile -Raw -Encoding UTF8
}

# Validate JSON (optional but helpful) with PS 5.1 compatibility
try {
  if ($PSVersionTable.PSVersion.Major -ge 6) {
    $null = $BodyJson | ConvertFrom-Json -Depth 100
  } else {
    $null = $BodyJson | ConvertFrom-Json
  }
} catch {
  throw "BodyJson is not valid JSON: $($_.Exception.Message)"
}

# Compute signature: Base64(HMAC-SHA256(secret, rawBody))
$hmac = [System.Security.Cryptography.HMACSHA256]::new([Text.Encoding]::UTF8.GetBytes($secretPlain))
try {
  $hash = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($BodyJson))
} finally {
  $hmac.Dispose()
}
$signature = [Convert]::ToBase64String($hash)

# Prepare headers and send
$headers = @{ 'X-Line-Signature' = $signature }
Write-Verbose ("Signature: {0}" -f $signature)

try {
  $response = Invoke-WebRequest -Uri $Url -Method Post -ContentType 'application/json' -Headers $headers -Body $BodyJson -ErrorAction Stop
  Write-Host ("StatusCode: {0}" -f $response.StatusCode)
  if ($OutFile) {
    $response.Content | Out-File -LiteralPath $OutFile -Encoding UTF8
    Write-Host ("Response written to: {0}" -f $OutFile)
  } else {
    # Print a small preview
    $preview = $response.Content
    if ($preview.Length -gt 500) { $preview = $preview.Substring(0,500) + '…' }
    Write-Host 'Response:'
    Write-Host $preview
  }
}
catch {
  $status = $null
  try { $status = $_.Exception.Response.StatusCode.value__ } catch { }
  if ($status) { Write-Host ("StatusCode: {0}" -f $status) }
  throw
}
finally {
  # Best-effort clear sensitive material
  $secretPlain = $null
}
