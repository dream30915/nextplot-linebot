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

## � Session & Auto-Naming (Quick Examples)

### Session Management

- เริ่ม session ใหม่เมื่อพิมพ์ข้อความรีเซ็ตว่า `........` หรือไม่มีข้อความใหม่เกิน 10 วินาที
- ระบบจะเก็บ `session_id` และ `last_activity_at` ใน user context เพื่อใช้ยึดโยงกับไฟล์และการสนทนา

ตัวอย่างไทม์ไลน์:

1) 12:00:00 ผู้ใช้ส่งข้อความแรก → สร้าง session 1  
2) 12:00:05 ส่งรูปภาพ → อยู่ใน session 1  
3) 12:00:20 เว้นเกิน 10 วินาที → ข้อความถัดไปจะเป็น session 2  
4) ผู้ใช้พิมพ์ `........` เมื่อไรก็ได้ → บังคับขึ้น session ใหม่ทันที

### Media Auto-Naming

- รูปแบบชื่อไฟล์: `{CODE}-{RUN}_{messageId}.{ext}`  
       - ตัวอย่าง: CODE = `WC-007`, RUN (session) = `3`, messageId = `abc123`, ext = `jpg`  
       - ชื่อไฟล์ = `WC-007-3_abc123.jpg`
- กรณีไม่มี CODE: ใช้ fallback เป็น `S{RUN}_{messageId}.{ext}`  
       - ตัวอย่าง: `S3_abc123.jpg`
- เส้นทางเก็บใน Supabase Storage (ตัวอย่าง): `line/YYYY/MM/DD/<filename>`

### ลองทดสอบอย่างเร็ว (PowerShell)

```powershell
# ส่ง payload ตัวอย่างไปยัง Cloud Run webhook
$url = "https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/line/webhook"
Invoke-RestMethod -Uri $url -Method Post -ContentType "application/json" -InFile ".\scripts\payloads\ai-greeting.json" | ConvertTo-Json -Compress
```

## 🧾 Supabase Schema Deployment

สคริปต์: `scripts/deploy-supabase-schema.ps1`  
ไฟล์สคีมา: `supabase/schema.sql`

ข้อกำหนดก่อนใช้งาน:

- ติดตั้ง `psql` และสามารถเรียกใช้งานได้ใน PATH
- ตั้งค่า `SUPABASE_DB_URL` ใน `.env` หรือส่ง `-DatabaseUrl` ตอนรัน
- รูปแบบ DB URL ตัวอย่าง: `postgresql://postgres:<PASSWORD>@db.<PROJECT_REF>.supabase.co:5432/postgres?sslmode=require`

ช่วยสร้างค่า SUPABASE_DB_URL อย่างเร็ว:

```powershell
# ถ้าตั้งค่า SUPABASE_URL และทราบรหัสผ่าน postgres (จาก Supabase)
./scripts/make-supabase-db-url.ps1 -DbPassword "<YOUR_DB_PASSWORD>"
```

การรันแบบ Dry-run (ไม่แก้ฐานข้อมูลจริง):

```powershell
./scripts/deploy-supabase-schema.ps1 -DryRun
```

การ Apply จริง (เขียนสคีมาลงฐานข้อมูล):

```powershell
./scripts/deploy-supabase-schema.ps1 -Apply
```

ถ้าไม่ได้ตั้งค่าใน `.env` สามารถส่งค่า URL ตรง ๆ ได้:

```powershell
./scripts/deploy-supabase-schema.ps1 -DryRun -DatabaseUrl "postgresql://postgres:<PWD>@db.<REF>.supabase.co:5432/postgres?sslmode=require"
```

## �🛠️ Development Workflow

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
