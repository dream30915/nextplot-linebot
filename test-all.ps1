[CmdletBinding()]
Param(
    [string]$EnvPath = ".\.env",
    [switch]$SkipLaravel,
    [switch]$SkipSupabase,
    [switch]$SkipLine,
    [switch]$SkipVercel,
    [switch]$SkipCloudRun,
    [switch]$SkipCloudBuild,
    [string]$LaravelHost = "127.0.0.1",
    [int]$LaravelPort = 8000,
    [string]$LaravelPingPath = "/api/nextplot/search?q=ping",
    [switch]$StartLaravelServer,
    [string]$CloudRunService = "nextplot-linebot",
    [string]$CloudRunRegion = "asia-southeast1",
    [string]$CloudRunProject = "",
    [string]$WebhookTestUrl = "",
    [string]$VercelProject = "",
    [string]$VercelScope = ""
)

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

function New-Result([bool]$Success, [string]$Detail) {
    return [ordered]@{ Success = $Success; Detail = $Detail }
}

function Read-Dotenv([string]$Path) {
    $map = @{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($rawLine in [System.IO.File]::ReadAllLines($Path)) {
        $line = $rawLine.Trim()
        if (-not $line) { continue }
        if ($line.StartsWith("#")) { continue }
        $pair = $rawLine.Split("=", 2)
        if ($pair.Length -lt 2) { continue }
        $key = $pair[0].Trim()
        $value = $pair[1]
        $value = $value.Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        elseif ($value.StartsWith("'") -and $value.EndsWith("'")) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $map[$key] = $value
    }
    return $map
}

function Get-EnvValue([hashtable]$Map, [string]$Key, [string]$Default = "") {
    if ($Map.ContainsKey($Key)) { return $Map[$Key] }
    return $Default
}

function Require-Env([hashtable]$Map, [string[]]$Keys) {
    $missing = @()
    foreach ($k in $Keys) {
        $v = Get-EnvValue -Map $Map -Key $k
        if ([string]::IsNullOrWhiteSpace($v)) { $missing += $k }
    }
    if ($missing.Count -gt 0) {
        throw "Missing environment values: $($missing -join ', ')"
    }
}

function Invoke-ToolCommand {
    Param(
        [string]$Command,
        [string[]]$Arguments = @(),
        [string]$DisplayName = $Command,
        [switch]$AllowFailure
    )

    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "Command '$Command' not found."
    }

    Push-Location $PSScriptRoot
    try {
        $global:LASTEXITCODE = 0
        $output = & $Command @Arguments 2>&1
        $exit = $LASTEXITCODE
    }
    finally { Pop-Location }

    if ($exit -ne 0 -and -not $AllowFailure) {
        $joined = ($Arguments -join ' ')
        $text = ($output | Out-String).Trim()
        throw "$DisplayName failed (exit $exit): $text"
    }

    return @{ ExitCode = $exit; Output = ($output | Out-String) }
}

function Join-Uri([string]$Base, [string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Base)) { return $Path }
    $trimBase = $Base.TrimEnd('/')
    $trimPath = $Path.TrimStart('/')
    return "$trimBase/$trimPath"
}

function Wait-HttpReady([string]$Url, [int]$TimeoutSec = 45) {
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    do {
        try {
            Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 | Out-Null
            return $true
        }
        catch { Start-Sleep -Milliseconds 750 }
    } while ((Get-Date) -lt $deadline)
    return $false
}

$results = [ordered]@{}
$envMap = Read-Dotenv -Path $EnvPath

$requiredKeys = @(
    "APP_KEY",
    "LINE_CHANNEL_ACCESS_TOKEN",
    "LINE_CHANNEL_SECRET",
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "SUPABASE_SERVICE_ROLE",
    "SUPABASE_BUCKET_NAME"
)

try {
    Require-Env -Map $envMap -Keys $requiredKeys
    $results[".env"] = New-Result $true "All required keys present."
}
catch {
    $results[".env"] = New-Result $false $_.Exception.Message
}

if (-not $SkipLaravel) {
    try {
        $artisan = Invoke-ToolCommand -Command "php" -Arguments @("artisan", "about", "--ansi") -DisplayName "php artisan about"
        $firstLine = ($artisan.Output -split "`r?`n")[0]
        if (-not $firstLine) { $firstLine = "artisan about executed." }
        $results["Laravel CLI"] = New-Result $true $firstLine
    }
    catch {
        $results["Laravel CLI"] = New-Result $false $_.Exception.Message
    }

    if ($StartLaravelServer) {
        $port = $LaravelPort
        $bind = $LaravelHost
        $serveArgs = @("artisan", "serve", "--host=$bind", "--port=$port")
        try {
            Write-Information "Starting temporary Laravel server on http://${bind}:${port} ..."
            $serveProcess = Start-Process -FilePath "php" -ArgumentList $serveArgs -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
            $pingUrl = Join-Uri ("http://${bind}:${port}") $LaravelPingPath
            if (Wait-HttpReady -Url $pingUrl -TimeoutSec 60) {
                try {
                    $response = Invoke-WebRequest -Uri $pingUrl -UseBasicParsing -TimeoutSec 10
                    $results["Laravel HTTP"] = New-Result $true "GET $LaravelPingPath -> $($response.StatusCode)"
                }
                catch {
                    $results["Laravel HTTP"] = New-Result $false "Ping failed: $($_.Exception.Message)"
                }
            }
            else {
                $results["Laravel HTTP"] = New-Result $false "Server not reachable within timeout."
            }
        }
        catch {
            $results["Laravel HTTP"] = New-Result $false $_.Exception.Message
        }
        finally {
            if ($serveProcess) {
                try { $serveProcess.Kill() } catch {}
            }
        }
    }
}

if (-not $SkipSupabase) {
    try {
        $supabaseUrl = Get-EnvValue -Map $envMap -Key "SUPABASE_URL"
        $supAnon = Get-EnvValue -Map $envMap -Key "SUPABASE_ANON_KEY"
        $supService = Get-EnvValue -Map $envMap -Key "SUPABASE_SERVICE_ROLE"
        $bucketName = Get-EnvValue -Map $envMap -Key "SUPABASE_BUCKET_NAME"
        $bucketEndpoint = Join-Uri $supabaseUrl "storage/v1/bucket"
        $headers = @{
            apikey        = $supAnon
            Authorization = "Bearer $supService"
        }
        $list = Invoke-RestMethod -Method Get -Uri $bucketEndpoint -Headers $headers -TimeoutSec 20
        $found = $false
        foreach ($b in $list) {
            if ($b.name -eq $bucketName) { $found = $true; break }
        }
        if (-not $found) {
            throw "Bucket '$bucketName' not found."
        }
        $results["Supabase"] = New-Result $true "Bucket '$bucketName' reachable."
    }
    catch {
        $results["Supabase"] = New-Result $false $_.Exception.Message
    }
}

if (-not $SkipLine) {
    try {
        $lineToken = Get-EnvValue -Map $envMap -Key "LINE_CHANNEL_ACCESS_TOKEN"
        $headers = @{ Authorization = "Bearer $lineToken" }
        $info = Invoke-RestMethod -Method Get -Uri "https://api.line.me/v2/bot/info" -Headers $headers -TimeoutSec 20
        $display = if ($info.displayName) { $info.displayName } else { "Bot" }
        $detail = "Bot: $display"
        if (-not [string]::IsNullOrWhiteSpace($WebhookTestUrl)) {
            try {
                $body = @{ endpoint = $WebhookTestUrl } | ConvertTo-Json -Compress
                Invoke-RestMethod -Method Post -Uri "https://api.line.me/v2/bot/channel/webhook/test" -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 30 | Out-Null
                $detail += "; webhook test invoked"
            }
            catch {
                $detail += "; webhook test failed: $($_.Exception.Message)"
            }
        }
        $results["LINE Messaging API"] = New-Result $true $detail
    }
    catch {
        $results["LINE Messaging API"] = New-Result $false $_.Exception.Message
    }
}

if (-not $SkipVercel) {
    try {
        # Vercel outputs version to stderr, suppress errors temporarily
        $prevErrPref = $ErrorActionPreference
        $ErrorActionPreference = "SilentlyContinue"
        
        $args = @("whoami")
        if ($VercelScope) { $args += @("--scope", $VercelScope) }
        
        Push-Location $PSScriptRoot
        try {
            $output = & vercel @args 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally { 
            Pop-Location
            $ErrorActionPreference = $prevErrPref
        }
        
        if ($exitCode -ne 0) {
            throw "Vercel whoami failed with exit code $exitCode"
        }
        
        $lines = ($output | Out-String) -split "`r?`n" | Where-Object { $_.Trim() -and $_ -notmatch "Vercel CLI|CategoryInfo|FullyQualifiedErrorId|At |node\.exe" }
        $username = ($lines | Select-Object -Last 1).Trim()
        if (-not $username) { $username = "authenticated" }
        $clean = "User: $username"
        
        # ตรวจสอบ deployments
        try {
            Push-Location $PSScriptRoot
            $lsOutput = & vercel ls --limit 1 2>&1
            $lsExit = $LASTEXITCODE
            Pop-Location
            
            if ($lsExit -eq 0) {
                $deployLines = ($lsOutput | Out-String) -split "`r?`n" | Where-Object { $_ -match "https://" }
                if ($deployLines.Count -gt 0) {
                    $clean += "; $($deployLines.Count) deployment(s) active"
                }
            }
        }
        catch {
            $clean += "; deployment check skipped"
        }
        
        $results["Vercel"] = New-Result $true $clean
    }
    catch {
        $results["Vercel"] = New-Result $false $_.Exception.Message
    }
}

if (-not $SkipCloudRun) {
    try {
        if ($CloudRunProject) {
            $projectId = $CloudRunProject
        }
        else {
            $projectInfo = Invoke-ToolCommand -Command "gcloud" -Arguments @("config", "get-value", "project")
            $projectId = $projectInfo.Output.Trim()
        }
        if (-not $projectId) { throw "Unable to resolve gcloud project." }
        $describeArgs = @(
            "run", "services", "describe", $CloudRunService,
            "--region", $CloudRunRegion,
            "--project", $projectId,
            "--format", "json"
        )
        $desc = Invoke-ToolCommand -Command "gcloud" -Arguments $describeArgs -DisplayName "gcloud run services describe"
        $json = $desc.Output.Trim()
        $service = $json | ConvertFrom-Json
        $url = $service.status.url
        $rev = $service.status.latestCreatedRevisionName
        $results["Cloud Run"] = New-Result $true "URL: $url | Latest revision: $rev"
    }
    catch {
        $results["Cloud Run"] = New-Result $false $_.Exception.Message
    }
}

if (-not $SkipCloudBuild) {
    try {
        $build = Invoke-ToolCommand -Command "gcloud" -Arguments @("builds", "list", "--limit", "1", "--format", "json") -DisplayName "gcloud builds list"
        $parsed = $build.Output.Trim()
        if ($parsed) {
            $buildInfo = $parsed | ConvertFrom-Json
            if ($buildInfo.Count -gt 0) {
                $item = $buildInfo[0]
                $detail = "Build $($item.id) status $($item.status)"
                $results["Cloud Build"] = New-Result $true $detail
            }
            else {
                $results["Cloud Build"] = New-Result $true "No builds found."
            }
        }
        else {
            $results["Cloud Build"] = New-Result $false "No response from gcloud builds."
        }
    }
    catch {
        $results["Cloud Build"] = New-Result $false $_.Exception.Message
    }
}

Write-Host "==== Verification Summary ===="
$failure = $false
foreach ($entry in $results.GetEnumerator()) {
    $status = if ($entry.Value.Success) { "OK" } else { "FAIL" }
    Write-Host ("[{0}] {1} - {2}" -f $status, $entry.Key, $entry.Value.Detail)
    if (-not $entry.Value.Success) { $failure = $true }
}

if ($failure) { exit 1 } else { exit 0 }
