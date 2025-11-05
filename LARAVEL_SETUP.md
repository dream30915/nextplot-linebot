# 🚀 Laravel Integration Setup Guide

## 📋 ขั้นตอนการติดตั้ง (Step-by-Step)

### 1️⃣ คัดลอกไฟล์ไปยัง Laravel Project

```powershell
# ตั้งค่าตัวแปร
$source = "C:\Users\msi\line-webhook-proxy\laravel-integration"
$dest = "C:\Users\msi\Desktop\nextplot-linebot"

# คัดลอก Service files
Copy-Item "$source\SupabaseService.php" "$dest\app\Services\SupabaseService.php" -Force
Copy-Item "$source\NextPlotService.php" "$dest\app\Services\NextPlotService.php" -Force

# คัดลอก Controller
Copy-Item "$source\LineWebhookController.php" "$dest\app\Http\Controllers\LineWebhookController.php" -Force

# คัดลอก Middleware
Copy-Item "$source\VerifyLineSignature.php" "$dest\app\Http\Middleware\VerifyLineSignature.php" -Force

# คัดลอก Config
Copy-Item "$source\nextplot.php" "$dest\config\nextplot.php" -Force

# คัดลอก .env example
Copy-Item "$source\.env.nextplot.example" "$dest\.env.nextplot.example" -Force

Write-Host "✅ คัดลอกไฟล์เรียบร้อย!" -ForegroundColor Green
```

### 2️⃣ สร้าง Services Directory

```powershell
cd C:\Users\msi\Desktop\nextplot-linebot

# สร้างโฟลเดอร์ Services ถ้ายังไม่มี
if (-not (Test-Path "app\Services")) {
    New-Item -ItemType Directory -Path "app\Services" -Force
}
```

### 3️⃣ อัปเดต composer.json

เปิดไฟล์ `composer.json` แล้วเพิ่ม:

```json
{
  "autoload": {
    "psr-4": {
      "App\\": "app/",
      "App\\Services\\": "app/Services/"
    }
  }
}
```

จากนั้นรัน:

```bash
composer dump-autoload
```

### 4️⃣ ติดตั้ง Dependencies

```bash
composer require guzzlehttp/guzzle
```

### 5️⃣ อัปเดต .env

เปิดไฟล์ `.env` แล้วเพิ่ม:

```env
# LINE Messaging API
LINE_CHANNEL_ACCESS_TOKEN=your_channel_access_token
LINE_CHANNEL_SECRET=your_channel_secret
LINE_USER_ID_ALLOWLIST=Ub58d192d370a1427a3c2eabc82f2d16b
LINE_SIGNATURE_RELAXED=false

# Supabase
SUPABASE_URL=https://xhcogxcmljnczwybqvia.supabase.co
SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE=your_service_role_key
SUPABASE_BUCKET_NAME=nextplot
```

### 6️⃣ อัปเดต routes/api.php

เปิดไฟล์ `routes/api.php` แล้วเพิ่ม:

```php
use App\Http\Controllers\LineWebhookController;

// Health check
Route::get('/health', function () {
    return response()->json([
        'ok' => true,
        'timestamp' => now()->toIso8601String(),
    ]);
});

// LINE webhook
Route::post('/line/webhook', [LineWebhookController::class, 'handle']);
```

### 7️⃣ Register Middleware (Optional)

เปิดไฟล์ `app/Http/Kernel.php` แล้วเพิ่มใน `$routeMiddleware`:

```php
protected $routeMiddleware = [
    // ... existing middleware
    'verify.line.signature' => \App\Http\Middleware\VerifyLineSignature::class,
];
```

จากนั้นอัปเดต route ใน `routes/api.php`:

```php
Route::post('/line/webhook', [LineWebhookController::class, 'handle'])
    ->middleware(['verify.line.signature']);
```

### 8️⃣ Deploy SQL Schema

เปิด Supabase SQL Editor และรันโค้ดจากไฟล์ `schema.sql`:

```sql
-- คัดลอกทั้งหมดจาก line-webhook-proxy/schema.sql
-- แล้ว paste และรันใน Supabase SQL Editor
```

### 9️⃣ Clear Laravel Cache

```bash
php artisan config:clear
php artisan cache:clear
php artisan route:clear
```

### 🔟 ทดสอบระบบ

```powershell
# Start Laravel server
php artisan serve

# ใน terminal อื่น - ทดสอบ health endpoint
curl http://localhost:8000/api/health

# Start Cloudflared tunnel (ถ้ามี)
.\bot-keepalive.ps1
```

---

## 📂 โครงสร้างไฟล์หลังติดตั้ง

```
nextplot-linebot/
├── app/
│   ├── Services/
│   │   ├── SupabaseService.php      ✅ ใหม่
│   │   └── NextPlotService.php      ✅ ใหม่
│   ├── Http/
│   │   ├── Controllers/
│   │   │   └── LineWebhookController.php  ✅ ใหม่
│   │   └── Middleware/
│   │       ├── Kernel.php           📝 แก้ไข
│   │       └── VerifyLineSignature.php    ✅ ใหม่
├── config/
│   └── nextplot.php                 ✅ ใหม่
├── routes/
│   └── api.php                      📝 แก้ไข
├── .env                             📝 แก้ไข
├── .env.nextplot.example            ✅ ใหม่
└── composer.json                    📝 แก้ไข
```

---

## ✅ Checklist การติดตั้ง

- [ ] คัดลอกไฟล์ Services (SupabaseService.php, NextPlotService.php)
- [ ] คัดลอกไฟล์ Controller (LineWebhookController.php)
- [ ] คัดลอกไฟล์ Middleware (VerifyLineSignature.php)
- [ ] คัดลอกไฟล์ Config (nextplot.php)
- [ ] สร้าง app/Services directory
- [ ] อัปเดต composer.json
- [ ] รัน `composer dump-autoload`
- [ ] ติดตั้ง Guzzle HTTP client
- [ ] อัปเดต .env ด้วย LINE และ Supabase credentials
- [ ] อัปเดต routes/api.php
- [ ] Register middleware ใน Kernel.php (optional)
- [ ] Deploy SQL schema ไปยัง Supabase
- [ ] Clear Laravel caches
- [ ] ทดสอบ health endpoint
- [ ] ทดสอบ webhook endpoint

---

## 🧪 การทดสอบ

### ทดสอบ Health Endpoint

```powershell
$response = Invoke-RestMethod -Uri "http://localhost:8000/api/health" -Method Get
$response | ConvertTo-Json
```

**ผลลัพธ์ที่คาดหวัง**:

```json
{
  "ok": true,
  "timestamp": "2025-10-19T10:30:00Z",
  "app": "NextPlot",
  "env": "local"
}
```

### ทดสอบ Webhook Endpoint (Local)

```powershell
$body = @{
  events = @(
    @{
      type = "message"
      replyToken = "test-token"
      timestamp = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
      source = @{ type = "user"; userId = "Ub58d192d370a1427a3c2eabc82f2d16b" }
      message = @{ type = "text"; text = "WC-007 โฉนด 8899" }
    }
  )
} | ConvertTo-Json -Depth 6

Invoke-RestMethod -Uri "http://localhost:8000/api/line/webhook" `
  -Method Post `
  -ContentType "application/json" `
  -Body $body
```

### ตรวจสอบ Logs

```bash
# ใน Laravel project
tail -f storage/logs/laravel.log
```

---

## 🔧 Troubleshooting

### ปัญหา: Class 'App\Services\SupabaseService' not found

**แก้ไข**:

```bash
composer dump-autoload
php artisan config:clear
```

### ปัญหา: Guzzle HTTP client not found

**แก้ไข**:

```bash
composer require guzzlehttp/guzzle
```

### ปัญหา: Config values are null

**แก้ไข**:

```bash
php artisan config:clear
php artisan cache:clear
```

### ปัญหา: Middleware not registered

**แก้ไข**: ตรวจสอบว่าเพิ่ม middleware ใน `app/Http/Kernel.php` แล้ว

### ปัญหา: Route not found

**แก้ไข**:

```bash
php artisan route:list
php artisan route:clear
```

---

## 🎯 ขั้นตอนถัดไป

หลังจากติดตั้งเสร็จ:

1. **ตั้งค่า LINE Webhook URL**
   - ไปที่ <https://developers.line.biz/console/>
   - ตั้ง Webhook URL: `https://your-domain/api/line/webhook`
   - หรือใช้ Cloudflared tunnel URL

2. **ทดสอบระบบ**
   - ส่งข้อความผ่าน LINE: "WC-007 โฉนด 8899"
   - ตรวจสอบว่าบันทึกลง Supabase
   - ตรวจสอบว่า Quick Reply ทำงาน

3. **Deploy to Production**
   - Push code to Git
   - Deploy Laravel app
   - Update LINE webhook URL

---

**Version**: 1.0.0  
**Last Updated**: 2025-10-19  
**Status**: ✅ Ready for Integration
