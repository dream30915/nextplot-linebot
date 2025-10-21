# Check Cloud Build Status
param(
    [switch]$Follow = $false,
    [int]$RefreshSeconds = 10
)

Write-Host "`n=== Cloud Build Status Monitor ===" -ForegroundColor Cyan

if ($Follow) {
    Write-Host "Monitoring build status... (Press Ctrl+C to stop)`n" -ForegroundColor Yellow
    
    while ($true) {
        Clear-Host
        Write-Host "=== Cloud Build Status Monitor ===" -ForegroundColor Cyan
        Write-Host "Time: $(Get-Date -Format 'HH:mm:ss')`n" -ForegroundColor Gray
        
        $build = gcloud builds list --limit=1 --format=json | ConvertFrom-Json
        
        if ($build) {
            $id = $build[0].id.Substring(0, 8)
            $status = $build[0].status
            $createTime = $build[0].createTime
            $duration = if ($build[0].timing.BUILD.endTime) {
                $start = [DateTime]::Parse($build[0].timing.BUILD.startTime)
                $end = [DateTime]::Parse($build[0].timing.BUILD.endTime)
                ($end - $start).TotalSeconds
            }
            else {
                "In progress..."
            }
            
            Write-Host "Build ID     : $id..." -ForegroundColor White
            Write-Host "Status       : " -NoNewline
            
            switch ($status) {
                "WORKING" { Write-Host $status -ForegroundColor Yellow }
                "SUCCESS" { Write-Host $status -ForegroundColor Green }
                "FAILURE" { Write-Host $status -ForegroundColor Red }
                default { Write-Host $status -ForegroundColor Gray }
            }
            
            Write-Host "Started      : $createTime" -ForegroundColor Gray
            Write-Host "Duration     : $duration seconds" -ForegroundColor Gray
            
            if ($build[0].logUrl) {
                Write-Host "Logs         : $($build[0].logUrl)" -ForegroundColor Cyan
            }
            
            if ($status -eq "SUCCESS") {
                Write-Host "`n✅ Build completed successfully!" -ForegroundColor Green
                Write-Host "Checking Cloud Run deployment...`n" -ForegroundColor Yellow
                
                $service = gcloud run services describe nextplot-linebot --region asia-southeast1 --format=json | ConvertFrom-Json
                if ($service) {
                    Write-Host "Service      : nextplot-linebot" -ForegroundColor White
                    Write-Host "URL          : $($service.status.url)" -ForegroundColor Cyan
                    Write-Host "Revision     : $($service.status.latestReadyRevisionName)" -ForegroundColor Gray
                    Write-Host "`n✅ Ready to switch webhook!" -ForegroundColor Green
                }
                break
            }
            elseif ($status -eq "FAILURE") {
                Write-Host "`n❌ Build failed! Check logs above." -ForegroundColor Red
                break
            }
        }
        else {
            Write-Host "No builds found." -ForegroundColor Yellow
        }
        
        Write-Host "`nRefreshing in $RefreshSeconds seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds $RefreshSeconds
    }
}
else {
    # One-time check
    $build = gcloud builds list --limit=1 --format=json | ConvertFrom-Json
    
    if ($build) {
        $status = $build[0].status
        $createTime = $build[0].createTime
        
        Write-Host "Latest Build:" -ForegroundColor White
        Write-Host "  ID       : $($build[0].id)" -ForegroundColor Gray
        Write-Host "  Status   : " -NoNewline
        
        switch ($status) {
            "WORKING" { Write-Host $status -ForegroundColor Yellow }
            "SUCCESS" { Write-Host $status -ForegroundColor Green }
            "FAILURE" { Write-Host $status -ForegroundColor Red }
            default { Write-Host $status -ForegroundColor Gray }
        }
        
        Write-Host "  Started  : $createTime" -ForegroundColor Gray
        Write-Host "  Logs     : $($build[0].logUrl)" -ForegroundColor Cyan
        
        Write-Host "`nRun with -Follow to monitor continuously" -ForegroundColor Yellow
    }
    else {
        Write-Host "No builds found." -ForegroundColor Yellow
    }
}

Write-Host ""
