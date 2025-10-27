# 🤖 NextPlot LINE Bot

![CI](https://github.com/dream30915/nextplot-linebot/actions/workflows/ci.yml/badge.svg)

NextPlot คือ LINE Bot ที่ใช้ Laravel 12 และ AI เพื่อตอบคำถามและให้บริการผู้ใช้งานผ่าน LINE Messaging API

## ✨ คุณสมบัติหลัก

- 🤖 **AI-Powered Responses** - ใช้ NLP ในการค้นหาและตอบคำถาม
- 📊 **NextPlot Integration** - เชื่อมต่อกับระบบ NextPlot สำหรับข้อมูลและการวิเคราะห์
- ☁️ **Multi-Cloud Architecture** - รองรับ Google Cloud Run (Primary) และ Vercel (Backup)
- 💾 **Supabase Storage** - จัดเก็บข้อมูลและไฟล์บน Supabase
- 🔒 **Secure & Validated** - มีการตรวจสอบ LINE Signature และ User Allowlist

## 🏗️ สถาปัตยกรรม

```
┌─────────────┐
│  LINE User  │
└──────┬──────┘
       │
       ▼
┌─────────────────────────────────────┐
│     LINE Messaging API Platform     │
└──────┬──────────────────────────────┘
       │
       │ Webhook (Primary or Backup)
       │
    ┌──┴────────────────────┐
    │                       │
    ▼                       ▼
┌─────────────────┐   ┌──────────────┐
│  Cloud Run      │   │   Vercel     │
│  (Primary)      │   │   (Backup)   │
│  Laravel App    │   │   Serverless │
└────────┬────────┘   └──────┬───────┘
         │                   │
         └───────┬───────────┘
                 │
                 ▼
         ┌──────────────┐
         │   Supabase   │
         │   Storage    │
         └──────────────┘
```

**Primary**: Google Cloud Run (2M requests/month Free Tier)  
**Backup**: Vercel (100GB bandwidth/month Free Tier)  
**Storage**: Supabase (Bucket: `nextplot`)

## 🚀 Quick Start

### 1. ติดตั้ง Dependencies

```powershell
# PHP Dependencies
composer install

# Node.js Dependencies (ถ้ามี)
npm install
```

### 2. ตั้งค่า Environment Variables

สร้างไฟล์ `.env` จาก `.env.example`:

```powershell
cp .env.example .env
```

แก้ไขค่าเหล่านี้ในไฟล์ `.env`:

```env
# LINE Messaging API
LINE_CHANNEL_ACCESS_TOKEN="your-channel-access-token"
LINE_CHANNEL_SECRET="your-channel-secret"
LINE_USER_ID_ALLOWLIST="user-id-1,user-id-2"

# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY="your-anon-key"
SUPABASE_SERVICE_ROLE="your-service-role-key"
SUPABASE_BUCKET_NAME=nextplot
```

### 3. รัน Development Server

```powershell
# วิธี 1: รัน Laravel + Cloudflare Tunnel พร้อมกัน
.\run-all.ps1

# วิธี 2: รัน Laravel เท่านั้น
php artisan serve
```

### 4. ทดสอบระบบ

```powershell
# รันการทดสอบครบวงจร (8 tests)
.\test-all.ps1
```

## 📋 สคริปต์ที่มีให้ใช้งาน

| สคริปต์ | คำอธิบาย |
|---------|----------|
| `.\test-all.ps1` | ทดสอบการเชื่อมต่อทุก service (8 tests) |
| `.\run-all.ps1` | รัน Laravel + Cloudflare Tunnel |
| `.\run-dev.ps1` | รัน Laravel development server |
| `.\switch-webhook.ps1` | สลับ LINE webhook ระหว่าง Cloud Run และ Vercel |
| `.\setup.ps1` | ติดตั้งและตั้งค่าโปรเจกต์ครั้งแรก |

## 🔄 การจัดการ Webhook

### ตรวจสอบสถานะ Webhook ปัจจุบัน

```powershell
.\switch-webhook.ps1 -Target status
```

### สลับไปใช้ Cloud Run (Production)

```powershell
.\switch-webhook.ps1 -Target cloudrun
```

### สลับไปใช้ Vercel (Backup)

```powershell
.\switch-webhook.ps1 -Target vercel
```

## 🧪 การทดสอบ

### ทดสอบทุก Service

```powershell
.\test-all.ps1
```

ระบบจะทดสอบ:

- ✅ `.env` configuration
- ✅ Laravel CLI
- ✅ Laravel HTTP server
- ✅ Supabase connection
- ✅ LINE Messaging API
- ✅ Vercel deployment
- ✅ Google Cloud Run
- ✅ Google Cloud Build

### ทดสอบด้วย Unit Tests

```powershell
php artisan test
```

### Static Analysis & Coding Standards

```powershell
# PHPStan (level configurable in phpstan.neon.dist)
composer phpstan

# PHP-CS-Fixer (check only)
composer php-cs-fixer

# PHP-CS-Fixer (apply fixes)
composer php-cs-fixer:fix
```

### Post-deploy Health Check

```powershell
.\u0073cripts\post-deploy-health.ps1 -Url "https://<your-cloud-run-url>/api/health" -Attempts 10 -IntervalSec 6
```

## 📦 Deployment

### Deploy ไป Google Cloud Run

```powershell
# Deploy ด้วย Cloud Build
gcloud builds submit --config cloudbuild.yaml

# หรือ Deploy โดยตรง
gcloud run deploy nextplot-linebot --source .
```

### Deploy ไป Vercel

```powershell
# Deploy to Production
vercel --prod

# Preview Deployment
vercel
```

## 🛠️ Development Workflow

### 1. Local Development

```powershell
# เริ่ม Laravel server
php artisan serve

# เริ่ม Cloudflare Tunnel (สำหรับทดสอบ webhook)
.\run-all.ps1
```

### 2. Testing

```powershell
# รันการทดสอบ
.\test-all.ps1

# ทดสอบ webhook จาก LINE
# ไปที่ LINE Developers Console > Webhook Settings > Test
```

### 3. Deployment

```powershell
# Push code ขึ้น GitHub
git add .
git commit -m "Update features"
git push

# Deploy to Cloud Run
gcloud builds submit --config cloudbuild.yaml

# Deploy to Vercel (backup)
vercel --prod
```

## 📝 เอกสารเพิ่มเติม

- [DEPLOYMENT.md](DEPLOYMENT.md) - คู่มือการ deploy และ failover
- [QUICK_START.md](QUICK_START.md) - เริ่มต้นใช้งานอย่างรวดเร็ว
- [SETUP_GUIDE.md](SETUP_GUIDE.md) - คู่มือการติดตั้งแบบละเอียด
- [LARAVEL_SETUP.md](LARAVEL_SETUP.md) - การตั้งค่า Laravel
- [NEXTPLOT.md](NEXTPLOT.md) - เอกสาร NextPlot API
- [Runbook: Troubleshooting & Operations](how-to-guides/runbook-line-bot-troubleshooting.md) - วิธีแก้ปัญหา 401/400/429, การดู logs และแนวทาง deploy

## 🔧 Troubleshooting

### Webhook ไม่ทำงาน

```powershell
# 1. ตรวจสอบ webhook URL ปัจจุบัน
.\switch-webhook.ps1 -Target status

# 2. ตรวจสอบการเชื่อมต่อ Cloud Run
.\test-all.ps1

# 3. ตรวจสอบ logs
gcloud run logs read nextplot-linebot --limit 50
```

### Supabase Connection Error

```powershell
# ตรวจสอบ JWT keys ใน .env ว่าไม่มี prefix "anon:" หรือ "service_role:"
# ควรเป็น: SUPABASE_ANON_KEY="eyJhbGci..."
```

### LINE Signature Validation Failed

```env
# ตั้งค่าใน .env
LINE_SIGNATURE_RELAXED="true"
```

## 🌟 Free Tier Limits

| Service | Free Tier |
|---------|-----------|
| Google Cloud Run | 2M requests/month |
| Vercel | 100GB bandwidth/month |
| Supabase | 500MB database + 1GB storage |
| Cloudflare Tunnel | Unlimited (for development) |

## 🔐 Security

- ไฟล์ `.env` ถูกระบุใน `.gitignore` แล้ว - **ห้าม commit ขึ้น Git**
- LINE Signature จะถูก verify ทุก webhook request
- User Allowlist จำกัดผู้ใช้ที่สามารถใช้ bot ได้

## 📞 Support

หากมีปัญหาหรือคำถาม:

1. ตรวจสอบ [DEPLOYMENT.md](DEPLOYMENT.md) สำหรับคำแนะนำ failover
2. รัน `.\test-all.ps1` เพื่อวินิจฉัยปัญหา
3. ตรวจสอบ Cloud Run logs: `gcloud run logs read nextplot-linebot`

## 📄 License

This project is built on Laravel which is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).

---

Made with ❤️ using Laravel 12, LINE Messaging API, and Supabase
