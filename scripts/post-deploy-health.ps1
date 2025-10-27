param(
    [Parameter(Mandatory=$true)][string]$Url,
    [int]$Attempts = 10,
    [int]$IntervalSec = 6
)

Write-Host "[post-deploy-health] Checking $Url ($Attempts attempts, every $IntervalSec sec)" -ForegroundColor Cyan

for ($i = 1; $i -le $Attempts; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10
        if ($resp.StatusCode -eq 200) {
            Write-Host "[post-deploy-health] OK (200) on attempt #$i" -ForegroundColor Green
            exit 0
        }
        Write-Warning "[post-deploy-health] Non-200: $($resp.StatusCode) on attempt #$i"
    }
    catch {
        Write-Warning "[post-deploy-health] Error: $($_.Exception.Message) on attempt #$i"
    }
    Start-Sleep -Seconds $IntervalSec
}

Write-Error "[post-deploy-health] Health check failed for $Url after $Attempts attempts"
exit 1
