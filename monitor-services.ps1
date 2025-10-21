<#
monitor-services.ps1
Continuous monitoring script for NextPlot services with automatic webhook failover
#>

[CmdletBinding()]
param(
    [int]$IntervalSeconds = 300,  # Check every 5 minutes
    [int]$MaxFailures = 3,        # Failover after 3 consecutive failures
    [switch]$AutoFailover = $false,  # Enable automatic failover
    [switch]$NotifyOnly = $false     # Only notify, don't failover
)

$ErrorActionPreference = 'Continue'

$script:CloudRunFailCount = 0
$script:CurrentPrimary = 'cloudrun'

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $color = switch ($Level) {
        'ERROR' { 'Red' }
        'WARN' { 'Yellow' }
        'SUCCESS' { 'Green' }
        default { 'White' }
    }
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
    
    # Log to file
    $logFile = "logs\monitor-$(Get-Date -Format 'yyyy-MM-dd').log"
    if (-not (Test-Path 'logs')) { New-Item -Type Directory -Path 'logs' -Force | Out-Null }
    Add-Content -Path $logFile -Value "[$timestamp] [$Level] $Message"
}

function Test-CloudRunHealth {
    try {
        $url = 'https://nextplot-linebot-656d4rnjja-as.a.run.app/api/health'
        $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "Cloud Run health check OK (Status: $($response.StatusCode))" 'SUCCESS'
            return $true
        }
        Write-Log "Cloud Run health check failed (Status: $($response.StatusCode))" 'WARN'
        return $false
    }
    catch {
        Write-Log "Cloud Run health check error: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Test-VercelHealth {
    try {
        $url = 'https://nextplotlinebot.vercel.app/api/health'
        $response = Invoke-WebRequest -Uri $url -Method Get -TimeoutSec 10 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Log "Vercel health check OK (Status: $($response.StatusCode))" 'SUCCESS'
            return $true
        }
        Write-Log "Vercel health check failed (Status: $($response.StatusCode))" 'WARN'
        return $false
    }
    catch {
        Write-Log "Vercel health check error: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Get-WebhookStatus {
    try {
        $result = & ".\switch-webhook.ps1" -Target status 2>&1 | Out-String
        if ($result -match 'Cloud Run') {
            return 'cloudrun'
        }
        elseif ($result -match 'Vercel') {
            return 'vercel'
        }
        return 'unknown'
    }
    catch {
        Write-Log "Failed to get webhook status: $($_.Exception.Message)" 'ERROR'
        return 'unknown'
    }
}

function Invoke-Failover {
    param([string]$TargetService)
    
    Write-Log "Initiating failover to $TargetService..." 'WARN'
    
    if ($NotifyOnly) {
        Write-Log "NOTIFY ONLY MODE: Would switch to $TargetService" 'WARN'
        # TODO: Send notification (email, LINE, etc.)
        return $false
    }
    
    if (-not $AutoFailover) {
        Write-Log "Auto-failover disabled. Manual intervention required." 'WARN'
        Write-Log "Run: .\switch-webhook.ps1 -Target $TargetService" 'INFO'
        # TODO: Send notification
        return $false
    }
    
    try {
        Write-Log "Executing webhook switch..." 'INFO'
        & ".\switch-webhook.ps1" -Target $TargetService
        
        Start-Sleep -Seconds 3
        $newStatus = Get-WebhookStatus
        
        if ($newStatus -eq $TargetService) {
            Write-Log "Failover successful! Now using $TargetService" 'SUCCESS'
            $script:CurrentPrimary = $TargetService
            return $true
        }
        else {
            Write-Log "Failover verification failed" 'ERROR'
            return $false
        }
    }
    catch {
        Write-Log "Failover failed: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# Main monitoring loop
Write-Host ""
Write-Host "NextPlot Service Monitor" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan
Write-Host "Interval: $IntervalSeconds seconds" -ForegroundColor White
Write-Host "Max Failures: $MaxFailures" -ForegroundColor White
Write-Host "Auto Failover: $AutoFailover" -ForegroundColor $(if ($AutoFailover) { 'Green' } else { 'Yellow' })
Write-Host "Notify Only: $NotifyOnly" -ForegroundColor $(if ($NotifyOnly) { 'Yellow' } else { 'White' })
Write-Host ""

Write-Log "Monitor started"

try {
    while ($true) {
        Write-Host ""
        Write-Host "--- Health Check $(Get-Date -Format 'HH:mm:ss') ---" -ForegroundColor Cyan
        
        # Check current webhook status
        $currentWebhook = Get-WebhookStatus
        Write-Log "Current webhook: $currentWebhook"
        
        # Check Cloud Run
        $cloudRunOk = Test-CloudRunHealth
        
        # Check Vercel
        $vercelOk = Test-VercelHealth
        
        # Failover logic
        if ($currentWebhook -eq 'cloudrun' -and -not $cloudRunOk) {
            $script:CloudRunFailCount++
            Write-Log "Cloud Run failure count: $script:CloudRunFailCount / $MaxFailures" 'WARN'
            
            if ($script:CloudRunFailCount -ge $MaxFailures) {
                if ($vercelOk) {
                    Write-Log "Cloud Run failed $MaxFailures times. Initiating failover to Vercel..." 'ERROR'
                    Invoke-Failover -TargetService 'vercel'
                    $script:CloudRunFailCount = 0
                }
                else {
                    Write-Log "Cloud Run failed but Vercel is also unhealthy. No failover." 'ERROR'
                }
            }
        }
        elseif ($currentWebhook -eq 'cloudrun' -and $cloudRunOk) {
            if ($script:CloudRunFailCount -gt 0) {
                Write-Log "Cloud Run recovered" 'SUCCESS'
            }
            $script:CloudRunFailCount = 0
        }
        elseif ($currentWebhook -eq 'vercel' -and $cloudRunOk) {
            Write-Log "Cloud Run is healthy. Consider switching back to primary." 'INFO'
            # Optional: Auto-recovery to Cloud Run
            # Invoke-Failover -TargetService 'cloudrun'
        }
        
        # Wait for next check
        Write-Host ""
        Write-Log "Next check in $IntervalSeconds seconds... (Press Ctrl+C to stop)"
        Start-Sleep -Seconds $IntervalSeconds
    }
}
catch {
    Write-Log "Monitor stopped: $($_.Exception.Message)" 'ERROR'
}
finally {
    Write-Log "Monitor ended"
}
