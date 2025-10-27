# ✅ สรุปการแก้ไข docker-entrypoint.sh Build Context

## 🎯 ปัญหาที่พบ

### Build #1 (5f630cf1) - FAILURE

**สาเหตุ**: PHP Version Mismatch

- Dockerfile ใช้ `php:8.1-fpm`
- Laravel 12 + dependencies ต้องการ `php ^8.2`
- Composer ติดปัญหา lock file ไม่ match กับ PHP version

**Error Messages**:

```text
Root composer.json requires php ^8.2 but your php version (8.1.33) does not satisfy that requirement.
laravel/framework v12.34.0 requires php ^8.2
symfony/* packages require php >=8.2
```

## 🔧 การแก้ไข

### 1. ✅ ตรวจสอบไฟล์ใน Git

```powershell
git ls-files | Select-String docker-entrypoint.sh
# ผลลัพธ์: docker-entrypoint.sh ✅
```

**สถานะ**: ไฟล์ถูก tracked ใน Git อย่างถูกต้อง

### 2. ✅ ตรวจสอบ .gcloudignore

```ignore
# Git files
.git
.gitignore
**/.git
**/.gitignore

# Node modules
node_modules

# Vendor
vendor

# Do not exclude the entrypoint script
!docker-entrypoint.sh  ← ✅ บรรทัดนี้ทำให้ไฟล์ไม่ถูก ignore
```

**สถานะ**: มี `!docker-entrypoint.sh` explicit inclusion

### 3. ✅ ตรวจสอบ Dockerfile

```dockerfile
# Use official PHP image
FROM php:8.2-fpm  ← ✅ แก้จาก 8.1 เป็น 8.2

# ... (steps อื่น ๆ)

# Copy application files
COPY . .

# Copy entrypoint and ensure executable
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh  ← ✅
RUN chmod +x /usr/local/bin/docker-entrypoint.sh                ← ✅

# Expose port
EXPOSE 8080

# Use entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]              ← ✅
```

**สถานะ**:

- ✅ COPY docker-entrypoint.sh จาก root repo
- ✅ chmod +x เพื่อให้รันได้
- ✅ ENTRYPOINT ชี้ไปที่สคริปต์
- ✅ เปลี่ยนเป็น PHP 8.2

### 4. ✅ แปลง CRLF → LF

```powershell
# แปลง line endings สำหรับ Linux
(Get-Content docker-entrypoint.sh -Raw) -replace "`r`n", "`n" | Set-Content -NoNewline docker-entrypoint.sh -Encoding UTF8
```

**สถานะ**: แปลงเรียบร้อย, ตรวจสอบ shebang:

```bash
#!/bin/bash  ← ✅ ถูกต้อง
```

### 5. 📊 Build Status

#### Build #2 (df8af5b8) - 🔄 WORKING

**Build ID**: `df8af5b8-d4fe-4ab7-b8b5-e94f3ad1e19b`  
**Status**: WORKING  
**Started**: 2025-10-21T19:42:24+00:00  
**Changes Applied**:

- ✅ PHP 8.2-FPM (ตรงกับ Laravel 12 requirements)
- ✅ CRLF → LF conversion
- ✅ docker-entrypoint.sh tracked and not ignored
- ✅ Dockerfile มี COPY, chmod, ENTRYPOINT ครบ

**Logs**: <https://console.cloud.google.com/cloud-build/builds/df8af5b8-d4fe-4ab7-b8b5-e94f3ad1e19b?project=546634969975>

## 📝 Commits

### Commit #1: 4209457

```text
Fix: Ensure docker-entrypoint.sh is included in build and switch to PHP-FPM
- Update .gcloudignore to explicitly include docker-entrypoint.sh
- Simplify Dockerfile to use PHP 8.1-FPM base image
```

### Commit #2: 0159c74 (Current)

```text
Fix: Change to PHP 8.2-FPM and normalize line endings
- Update Dockerfile from PHP 8.1 to PHP 8.2 (required by Laravel 12)
- Convert docker-entrypoint.sh from CRLF to LF for Linux compatibility
- Ensure docker-entrypoint.sh is executable with chmod +x
- Confirm .gcloudignore includes !docker-entrypoint.sh
```

## 🔍 การตรวจสอบ Build Context (ถ้า Build ล้มเหลว)

### ดาวน์โหลดและตรวจสอบ Archive

```powershell
# 1. หา source archive
$BUILD_ID = "df8af5b8-d4fe-4ab7-b8b5-e94f3ad1e19b"
gcloud builds describe $BUILD_ID --project=nextplot-linebot-475618 --format="value(source.storageSource.bucket,source.storageSource.object)"

# 2. ดาวน์โหลด
gcloud storage cp gs://<BUCKET>/<OBJECT> ./source.tgz

# 3. ตรวจสอบว่ามีไฟล์หรือไม่
tar -tzf source.tgz | Select-String docker-entrypoint.sh
```

### หรือใช้สคริปต์อัตโนมัติ

```powershell
.\verify-build-context.ps1
# หรือระบุ Build ID
.\verify-build-context.ps1 -BuildId df8af5b8-d4fe-4ab7-b8b5-e94f3ad1e19b
```

## 📊 ติดตาม Build Real-time

```powershell
# ดู status
gcloud builds list --limit=1

# ดู log แบบ streaming
gcloud builds log df8af5b8-d4fe-4ab7-b8b5-e94f3ad1e19b --project=nextplot-linebot-475618 --stream

# ใช้สคริปต์ที่มี
.\check-build-status.ps1 -Follow
```

## 🎯 ขั้นตอนหลัง Build สำเร็จ

### 1. ทดสอบ Cloud Run

```powershell
# Health check
Invoke-WebRequest -Uri "https://nextplot-linebot-656d4rnjja-as.a.run.app/api/health"

# คาดหวัง: 200 OK (ไม่ใช่ 500)
```

### 2. ดู Logs

```powershell
gcloud run services logs read nextplot-linebot --region asia-southeast1 --limit 20
```

### 3. สลับ Webhook ไป Cloud Run

```powershell
.\switch-webhook.ps1 -Target cloudrun
```

### 4. ตรวจสอบใน LINE Console

- ไปที่ LINE Developers Console
- เข้า Messaging API → Webhook settings
- คลิก "Verify"
- คาดหวัง: "Success" ✅

## 🐛 Troubleshooting

### ถ้า Build ยังล้มเหลว

1. **ตรวจสอบ Archive**

   ```powershell
   .\verify-build-context.ps1 -BuildId <BUILD_ID>
   ```

2. **ดู Error Logs**

   ```powershell
   gcloud builds log <BUILD_ID> --project=nextplot-linebot-475618 | Select-Object -Last 50
   ```

3. **ตรวจสอบ Git Status**

   ```powershell
   git status
   git ls-files docker-entrypoint.sh
   ```

4. **ยืนยัน Line Endings**

   ```powershell
   # ดู hex dump บรรทัดแรก
   Format-Hex docker-entrypoint.sh -Count 50
   # หา 0D 0A (CRLF) หรือ 0A (LF)
   ```

### ถ้า Container รันไม่ได้

1. **ตรวจสอบ Logs**

   ```powershell
   gcloud run services logs read nextplot-linebot --region asia-southeast1
   ```

2. **ตรวจสอบ Secrets**

   ```powershell
   gcloud secrets versions access latest --secret="APP_KEY"
   gcloud secrets versions access latest --secret="LINE_CHANNEL_ACCESS_TOKEN"
   ```

3. **ทดสอบ Locally**

   ```powershell
   docker build -t test-linebot .
   docker run -p 8080:8080 -e APP_KEY="base64:..." test-linebot
   ```

## 📌 สรุปสถานะปัจจุบัน

| หัวข้อ | สถานะ | หมายเหตุ |
|--------|-------|----------|
| ไฟล์ใน Git | ✅ | docker-entrypoint.sh tracked |
| .gcloudignore | ✅ | มี !docker-entrypoint.sh |
| Dockerfile COPY | ✅ | COPY + chmod +x + ENTRYPOINT |
| Line Endings | ✅ | แปลง CRLF → LF แล้ว |
| PHP Version | ✅ | PHP 8.2-FPM (ตรงกับ Laravel 12) |
| Build #1 (5f630cf1) | ❌ FAILURE | PHP version mismatch |
| Build #2 (df8af5b8) | 🔄 WORKING | รอผลลัพธ์ |
| Vercel Backup | ✅ WORKING | <https://nextplotlinebot.vercel.app> |

## 🚀 คำสั่งด่วน

```powershell
# ตรวจสอบ Build
.\check-build-status.ps1

# ตรวจสอบ Build Context
.\verify-build-context.ps1

# ดู Logs
gcloud builds log df8af5b8-d4fe-4ab7-b8b5-e94f3ad1e19b --project=nextplot-linebot-475618

# ทดสอบ Cloud Run
Invoke-WebRequest -Uri "https://nextplot-linebot-656d4rnjja-as.a.run.app/api/health"

# สลับ Webhook
.\switch-webhook.ps1 -Target cloudrun

# ดู Cloud Run Logs
gcloud run services logs read nextplot-linebot --region asia-southeast1 --limit 20
```

---

**หมายเหตุ**: Build กำลังทำงานอยู่ คาดว่าจะเสร็จใน 5-7 นาที การแก้ไขครั้งนี้แก้ปัญหาหลัก (PHP version mismatch) และยืนยันว่า docker-entrypoint.sh จะถูกส่งเข้า build context อย่างถูกต้อง 🎉
