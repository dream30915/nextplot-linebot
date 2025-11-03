#!/usr/bin/env pwsh
# Verify docker-entrypoint.sh is included in Cloud Build (PowerShell 5.1 compatible)

param(
    [Parameter(Mandatory = $false)]
    [string]$BuildId = ""
)

Write-Host "`n========== Build Context Check ==========" -ForegroundColor Cyan

# 1. ตรวจสอบไฟล์ใน Git
Write-Host "`n1) Check file tracked in Git:" -ForegroundColor Yellow
$gitFiles = git ls-files | Select-String "docker-entrypoint.sh"
if ($gitFiles) {
    Write-Host "   OK Found file: $gitFiles" -ForegroundColor Green
}
else {
    Write-Host "   ERROR File not found in Git" -ForegroundColor Red
    exit 1
}

# 2. Check .gcloudignore
Write-Host "`n2) Check .gcloudignore:" -ForegroundColor Yellow
if (Test-Path .gcloudignore) {
    $gcloudignore = Get-Content .gcloudignore -Raw -Encoding UTF8
    if ($gcloudignore -match "!docker-entrypoint\.sh") {
        Write-Host "   OK Found !docker-entrypoint.sh in .gcloudignore" -ForegroundColor Green
    }
    else {
        Write-Host "   WARN !docker-entrypoint.sh not found - file may be ignored" -ForegroundColor Yellow
    }
} else {
    Write-Host "   WARN .gcloudignore not found" -ForegroundColor Yellow
}

# 3. ตรวจสอบ Dockerfile
Write-Host "`n3) Check Dockerfile:" -ForegroundColor Yellow
$dockerfile = Get-Content Dockerfile -Raw
$checks = @{
    "COPY docker-entrypoint.sh" = $dockerfile -match "COPY\s+docker-entrypoint\.sh"
    "chmod +x"                  = $dockerfile -match "chmod\s+\+x.*docker-entrypoint\.sh"
    "ENTRYPOINT"                = $dockerfile -match 'ENTRYPOINT\s+\["/usr/local/bin/docker-entrypoint\.sh"\]'
}

foreach ($check in $checks.GetEnumerator()) {
    if ($check.Value) {
        Write-Host "   OK $($check.Key)" -ForegroundColor Green
    }
    else {
        Write-Host "   ERROR Missing: $($check.Key)" -ForegroundColor Red
    }
}

# 4. ตรวจสอบ shebang
Write-Host "`n4) Check shebang:" -ForegroundColor Yellow
$firstLine = Get-Content docker-entrypoint.sh -First 1 -Encoding UTF8
if ($firstLine -match "^#!/bin/(bash|sh)") {
    Write-Host "   OK Shebang valid: $firstLine" -ForegroundColor Green
}
else {
    Write-Host "   WARN Shebang: $firstLine" -ForegroundColor Yellow
}

# 5. ตรวจสอบ Build ล่าสุด
Write-Host "`n5) Check Build:" -ForegroundColor Yellow
if ($BuildId -eq "") {
    $latestBuild = gcloud builds list --limit=1 --format="value(id)"
    $BuildId = $latestBuild
    Write-Host "   Latest Build ID: $BuildId" -ForegroundColor Cyan
}

$buildStatus = gcloud builds describe $BuildId --project=nextplot-linebot-475618 --format="value(status)" 2>$null
if ($buildStatus) {
    # Determine color separately to avoid parser issues on some PowerShell versions
    $statusColor = switch ($buildStatus) {
        "SUCCESS" { "Green" }
        "WORKING" { "Yellow" }
        "QUEUED" { "Cyan" }
        "FAILURE" { "Red" }
        default { "Gray" }
    }
    Write-Host "   Status: $buildStatus" -ForegroundColor $statusColor

    # ถ้า build ล้มเหลว ให้ดาวน์โหลด archive และตรวจสอบ
    if ($buildStatus -eq "FAILURE") {
    Write-Host "`n   Inspecting build archive..." -ForegroundColor Yellow

        # ดึง source archive path
        $sourceBucket = gcloud builds describe $BuildId --project=nextplot-linebot-475618 --format="value(source.storageSource.bucket)"
        $sourceObject = gcloud builds describe $BuildId --project=nextplot-linebot-475618 --format="value(source.storageSource.object)"

        if ($sourceBucket -and $sourceObject) {
            Write-Host "   Bucket: $sourceBucket" -ForegroundColor Gray
            Write-Host "   Object: $sourceObject" -ForegroundColor Gray

            $archivePath = "gs://$sourceBucket/$sourceObject"
            $localArchive = "./build-source-verify.tgz"

            Write-Host "   Downloading archive..." -ForegroundColor Gray
            gcloud storage cp $archivePath $localArchive 2>$null

            if (Test-Path $localArchive) {
                Write-Host "   OK Downloaded" -ForegroundColor Green

                # ตรวจสอบว่ามี docker-entrypoint.sh หรือไม่
                $entrypointInArchive = tar -tzf $localArchive | Select-String "docker-entrypoint.sh"
                if ($entrypointInArchive) {
                    Write-Host "   OK Found docker-entrypoint.sh in archive: $entrypointInArchive" -ForegroundColor Green
                }
                else {
                    Write-Host "   ERROR docker-entrypoint.sh not found in archive" -ForegroundColor Red
                    Write-Host "      File may be blocked by .gcloudignore or .gitignore" -ForegroundColor Red
                }

                # ลบไฟล์ชั่วคราว
                Remove-Item $localArchive -Force
            }
        }

        # แสดง error log
        Write-Host "`n   Last build log:" -ForegroundColor Yellow
        gcloud builds log $BuildId --project=nextplot-linebot-475618 2>$null | Select-Object -Last 30
    }
}
else {
    Write-Host "   ERROR Build ID not found: $BuildId" -ForegroundColor Red
}

Write-Host "`nCheck complete`n" -ForegroundColor Green
