#!/usr/bin/env pwsh
# สคริปต์ตรวจสอบว่า docker-entrypoint.sh ถูกส่งเข้า Cloud Build หรือไม่

param(
    [Parameter(Mandatory = $false)]
    [string]$BuildId = ""
)

Write-Host "`n🔍 ========== การตรวจสอบ Build Context ==========" -ForegroundColor Cyan

# 1. ตรวจสอบไฟล์ใน Git
Write-Host "`n1️⃣ ตรวจสอบไฟล์ถูก tracked ใน Git:" -ForegroundColor Yellow
$gitFiles = git ls-files | Select-String "docker-entrypoint.sh"
if ($gitFiles) {
    Write-Host "   ✅ พบไฟล์: $gitFiles" -ForegroundColor Green
}
else {
    Write-Host "   ❌ ไม่พบไฟล์ใน Git!" -ForegroundColor Red
    exit 1
}

# 2. ตรวจสอบ .gcloudignore
Write-Host "`n2️⃣ ตรวจสอบ .gcloudignore:" -ForegroundColor Yellow
$gcloudignore = Get-Content .gcloudignore -Raw
if ($gcloudignore -match "!docker-entrypoint\.sh") {
    Write-Host "   ✅ พบ !docker-entrypoint.sh ใน .gcloudignore" -ForegroundColor Green
}
else {
    Write-Host "   ⚠️  ไม่พบ !docker-entrypoint.sh - อาจถูก ignore!" -ForegroundColor Yellow
}

# 3. ตรวจสอบ Dockerfile
Write-Host "`n3️⃣ ตรวจสอบ Dockerfile:" -ForegroundColor Yellow
$dockerfile = Get-Content Dockerfile -Raw
$checks = @{
    "COPY docker-entrypoint.sh" = $dockerfile -match "COPY\s+docker-entrypoint\.sh"
    "chmod +x"                  = $dockerfile -match "chmod\s+\+x.*docker-entrypoint\.sh"
    "ENTRYPOINT"                = $dockerfile -match 'ENTRYPOINT\s+\["/usr/local/bin/docker-entrypoint\.sh"\]'
}

foreach ($check in $checks.GetEnumerator()) {
    if ($check.Value) {
        Write-Host "   ✅ $($check.Key)" -ForegroundColor Green
    }
    else {
        Write-Host "   ❌ ไม่พบ $($check.Key)" -ForegroundColor Red
    }
}

# 4. ตรวจสอบ shebang
Write-Host "`n4️⃣ ตรวจสอบ shebang:" -ForegroundColor Yellow
$firstLine = Get-Content docker-entrypoint.sh -First 1 -Encoding UTF8
if ($firstLine -match "^#!/bin/(bash|sh)") {
    Write-Host "   ✅ Shebang ถูกต้อง: $firstLine" -ForegroundColor Green
}
else {
    Write-Host "   ⚠️  Shebang: $firstLine" -ForegroundColor Yellow
}

# 5. ตรวจสอบ Build ล่าสุด
Write-Host "`n5️⃣ ตรวจสอบ Build:" -ForegroundColor Yellow
if ($BuildId -eq "") {
    $latestBuild = gcloud builds list --limit=1 --format="value(id)"
    $BuildId = $latestBuild
    Write-Host "   📋 Build ID ล่าสุด: $BuildId" -ForegroundColor Cyan
}

$buildStatus = gcloud builds describe $BuildId --project=nextplot-linebot-475618 --format="value(status)" 2>$null
if ($buildStatus) {
    Write-Host "   📊 Status: $buildStatus" -ForegroundColor $(
        switch ($buildStatus) {
            "SUCCESS" { "Green" }
            "WORKING" { "Yellow" }
            "QUEUED" { "Cyan" }
            "FAILURE" { "Red" }
            default { "Gray" }
        }
    )
    
    # ถ้า build ล้มเหลว ให้ดาวน์โหลด archive และตรวจสอบ
    if ($buildStatus -eq "FAILURE") {
        Write-Host "`n   🔍 กำลังตรวจสอบ build archive..." -ForegroundColor Yellow
        
        # ดึง source archive path
        $sourceBucket = gcloud builds describe $BuildId --project=nextplot-linebot-475618 --format="value(source.storageSource.bucket)"
        $sourceObject = gcloud builds describe $BuildId --project=nextplot-linebot-475618 --format="value(source.storageSource.object)"
        
        if ($sourceBucket -and $sourceObject) {
            Write-Host "   📦 Bucket: $sourceBucket" -ForegroundColor Gray
            Write-Host "   📦 Object: $sourceObject" -ForegroundColor Gray
            
            $archivePath = "gs://$sourceBucket/$sourceObject"
            $localArchive = "./build-source-verify.tgz"
            
            Write-Host "   ⬇️  กำลังดาวน์โหลด archive..." -ForegroundColor Gray
            gcloud storage cp $archivePath $localArchive 2>$null
            
            if (Test-Path $localArchive) {
                Write-Host "   ✅ ดาวน์โหลดสำเร็จ" -ForegroundColor Green
                
                # ตรวจสอบว่ามี docker-entrypoint.sh หรือไม่
                $entrypointInArchive = tar -tzf $localArchive | Select-String "docker-entrypoint.sh"
                if ($entrypointInArchive) {
                    Write-Host "   ✅ พบ docker-entrypoint.sh ใน archive: $entrypointInArchive" -ForegroundColor Green
                }
                else {
                    Write-Host "   ❌ ไม่พบ docker-entrypoint.sh ใน archive!" -ForegroundColor Red
                    Write-Host "      → ไฟล์อาจถูก .gcloudignore หรือ .gitignore บล็อก" -ForegroundColor Red
                }
                
                # ลบไฟล์ชั่วคราว
                Remove-Item $localArchive -Force
            }
        }
        
        # แสดง error log
        Write-Host "`n   📄 Log ล่าสุด:" -ForegroundColor Yellow
        gcloud builds log $BuildId --project=nextplot-linebot-475618 2>$null | Select-Object -Last 30
    }
}
else {
    Write-Host "   ❌ ไม่พบ Build ID: $BuildId" -ForegroundColor Red
}

Write-Host "`n✅ การตรวจสอบเสร็จสิ้น`n" -ForegroundColor Green
