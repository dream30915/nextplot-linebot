[CmdletBinding()]
Param(
    [string]$ServiceName = "nextplot-linebot",
    [string]$Region = "asia-southeast1",
    [string]$EnvPath = ".\.env",
    [switch]$Always200
)

$ErrorActionPreference = 'Stop'

function Read-Dotenv {
    param([string]$Path)
    $result = @{}
    if (-not (Test-Path $Path)) { throw ".env not found at $Path" }
    foreach ($line in Get-Content $Path) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $parts = $l -split '=', 2
        if ($parts.Length -lt 2) { continue }
        $k = $parts[0].Trim()
        $v = $parts[1].Trim()
        if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        $result[$k] = $v
    }
    return $result
}

Write-Host "Reading .env from $EnvPath" -ForegroundColor Cyan
$envMap = Read-Dotenv -Path $EnvPath

# Required basics for NextPlot + AI; include if present in .env
$keys = @(
    'LINE_CHANNEL_ACCESS_TOKEN','LINE_CHANNEL_SECRET','LINE_SIGNATURE_RELAXED',
    'OPENAI_API_KEY','OPENAI_CHAT_MODEL','OPENAI_TEMPERATURE','OPENAI_MAX_TOKENS','OPENAI_SYSTEM_PROMPT',
    'NEXTPLOT_CHAT_ENABLED','NEXTPLOT_CHAT_DRIVER',
    'SUPABASE_URL','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE','SUPABASE_BUCKET_NAME'
)

# Safe-mode toggle to stop LINE from retry storms
if ($Always200) { $envMap['LINE_WEBHOOK_ALWAYS_200'] = 'true' }

# Build --set-env-vars argument
$pairs = @()
foreach ($k in $keys) {
    if ($envMap.ContainsKey($k) -and $envMap[$k]) {
        $v = $envMap[$k]
        # escape commas
        $v = $v -replace ',', '\\,'
        $pairs += ("$k=$v")
    }
}
if ($envMap.ContainsKey('LINE_WEBHOOK_ALWAYS_200')) { $pairs += ("LINE_WEBHOOK_ALWAYS_200=" + $envMap['LINE_WEBHOOK_ALWAYS_200']) }

if ($pairs.Count -eq 0) {
    Write-Warning "No env vars found to set; continuing with deploy only."
}

$setArgs = $null
if ($pairs.Count -gt 0) { $setArgs = "--set-env-vars '" + ($pairs -join ',') + "'" }

Write-Host "Deploying $ServiceName to Cloud Run ($Region)..." -ForegroundColor Yellow

$cmd = @(
    'gcloud','run','deploy',$ServiceName,
    '--source','.',
    '--region',$Region,
    '--allow-unauthenticated'
)
# Proactively remove secrets/env vars for keys that may change type (secret <-> literal)
$resetKeys = @('LINE_CHANNEL_ACCESS_TOKEN','LINE_CHANNEL_SECRET','OPENAI_API_KEY','SUPABASE_ANON_KEY','SUPABASE_SERVICE_ROLE')
if ($resetKeys.Count -gt 0) {
    $cmd += ('--remove-secrets ' + ($resetKeys -join ','))
    $cmd += ('--remove-env-vars ' + ($resetKeys -join ','))
}
if ($setArgs) { $cmd += $setArgs }

$cmdLine = $cmd -join ' '
Write-Host $cmdLine -ForegroundColor DarkGray

& cmd /c $cmdLine
if ($LASTEXITCODE -ne 0) { throw "gcloud run deploy failed ($LASTEXITCODE)" }

Write-Host "✅ Deployment complete." -ForegroundColor Green
