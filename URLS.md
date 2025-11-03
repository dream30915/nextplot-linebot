# 📍 NextPlot URLs & Endpoints Reference

เอกสารรวม URLs และ endpoints ทั้งหมดที่ใช้ในระบบ NextPlot LINE Bot

## 🎯 LINE Webhook Configuration

### ตรวจสอบ Webhook ปัจจุบัน

```powershell
.\switch-webhook.ps1 -Target status
```

### Production (Primary)

```
https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/line/webhook
```

**ตั้งค่า:**

```powershell
.\switch-webhook.ps1 -Target cloudrun
```

### Backup (Vercel)

```
https://nextplotlinebot.vercel.app/api/line/webhook
```

**ตั้งค่า:**

```powershell
.\switch-webhook.ps1 -Target vercel
```

### Development (Cloudflare Tunnel)

```
https://[random-name].trycloudflare.com/api/line/webhook
```

**หมายเหตุ:** URL เปลี่ยนทุกครั้งที่รัน `.\run-all.ps1`

---

## ☁️ Google Cloud Run (Primary)

### Service URLs

```
Base URL:     https://nextplot-linebot-546634969975.asia-southeast1.run.app
Health Check: https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/health
Webhook:      https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/line/webhook
NextPlot API: https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/nextplot/search
```

### ตรวจสอบสถานะ

```powershell
# ดู URL
gcloud run services describe nextplot-linebot --region asia-southeast1 --format="value(status.url)"

# ดู revision ล่าสุด
gcloud run revisions list --service nextplot-linebot --region asia-southeast1 --limit 1

# ดู logs
gcloud run logs read nextplot-linebot --limit 50
```

### ข้อมูลเพิ่มเติม

- **Region:** asia-southeast1 (Singapore)
- **Service Name:** nextplot-linebot
- **Latest Revision:** nextplot-linebot-00005-ldw
- **Free Tier:** 2,000,000 requests/month

---

## 🔷 Vercel (Backup)

### Service URLs

```
Base URL:     https://nextplotlinebot.vercel.app
Health Check: https://nextplotlinebot.vercel.app/api/health
Webhook:      https://nextplotlinebot.vercel.app/api/line/webhook
```

### ตรวจสอบสถานะ

```powershell
# List deployments
vercel ls

# View logs
vercel logs nextplotlinebot

# View environment variables
vercel env ls
```

### ข้อมูลเพิ่มเติม

- **Project:** nextplot.linebot
- **Team/User:** nextplot
- **Region:** sin1 (Singapore)
- **Free Tier:** 100GB bandwidth/month

---

## 💾 Supabase Storage

### Storage URLs

```
Project URL:  https://xhcogxcmljnczwybqvia.supabase.co
Storage API:  https://xhcogxcmljnczwybqvia.supabase.co/storage/v1
Bucket Name:  nextplot
```

### ตรวจสอบสถานะ

```powershell
# Test bucket access (from test-all.ps1)
$headers = @{
    "Authorization" = "Bearer $env:SUPABASE_ANON_KEY"
    "apikey" = "$env:SUPABASE_ANON_KEY"
}
Invoke-RestMethod -Uri "https://xhcogxcmljnczwybqvia.supabase.co/storage/v1/bucket/nextplot" -Headers $headers
```

### ข้อมูลเพิ่มเติม

- **Project ID:** xhcogxcmljnczwybqvia
- **Region:** Singapore
- **Free Tier:** 1GB storage

---

## 🔧 Local Development

### Laravel Development Server

```
Base URL:     http://127.0.0.1:8000
Health Check: http://127.0.0.1:8000/api/health
Webhook:      http://127.0.0.1:8000/api/line/webhook
NextPlot API: http://127.0.0.1:8000/api/nextplot/search
```

**เริ่มต้น:**

```powershell
php artisan serve
```

### Cloudflare Tunnel (Development Webhook)

```
Dynamic URL: https://[random].trycloudflare.com
Webhook:     https://[random].trycloudflare.com/api/line/webhook
```

**เริ่มต้น:**

```powershell
.\run-all.ps1
# หรือ
.\run-dev.ps1
```

---

## 🧪 Health Check Endpoints

| Service | Health URL | Expected Response |
|---------|-----------|-------------------|
| **Cloud Run** | `https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/health` | `{"status":"healthy","service":"laravel",...}` |
| **Vercel** | `https://nextplotlinebot.vercel.app/api/health` | `{"status":"healthy","service":"vercel",...}` |
| **Local** | `http://127.0.0.1:8000/api/health` | `{"status":"healthy","service":"laravel",...}` |

### ทดสอบ Health Checks

```powershell
# Cloud Run
curl https://nextplot-linebot-546634969975.asia-southeast1.run.app/api/health

# Vercel
curl https://nextplotlinebot.vercel.app/api/health

# Local
curl http://127.0.0.1:8000/api/health
```

---

## 📊 LINE Platform

### LINE Developers Console

```
Console:     https://developers.line.biz/console/
Bot Name:    NextPlot
Channel Type: Messaging API
```

### LINE Messaging API Endpoints

```
Bot Info:       https://api.line.me/v2/bot/info
Get Webhook:    https://api.line.me/v2/bot/channel/webhook/endpoint
Set Webhook:    PUT https://api.line.me/v2/bot/channel/webhook/endpoint
Test Webhook:   POST https://api.line.me/v2/bot/channel/webhook/test
```

---

## 🔄 Quick Commands

### ตรวจสอบทุก Service

```powershell
.\test-all.ps1
```

### สลับ Webhook

```powershell
# ดูสถานะปัจจุบัน
.\switch-webhook.ps1 -Target status

# เปลี่ยนเป็น Cloud Run
.\switch-webhook.ps1 -Target cloudrun

# เปลี่ยนเป็น Vercel
.\switch-webhook.ps1 -Target vercel
```

### Deploy Services

```powershell
# Deploy to Cloud Run
gcloud builds submit --config cloudbuild.yaml

# Deploy to Vercel
vercel --prod
```

### Monitor Services

```powershell
# Run monitoring (notify only)
.\monitor-services.ps1 -NotifyOnly

# Run with auto-failover
.\monitor-services.ps1 -AutoFailover -IntervalSeconds 300
```

---

## 📝 Environment Variables

### ตำแหน่งที่ต้องตั้งค่า

| Variable | .env (Local) | Cloud Run | Vercel |
|----------|--------------|-----------|--------|
| `LINE_CHANNEL_ACCESS_TOKEN` | ✅ | ✅ (Secret Manager) | ✅ |
| `LINE_CHANNEL_SECRET` | ✅ | ✅ (Secret Manager) | ✅ |
| `SUPABASE_URL` | ✅ | ✅ (Secret Manager) | ✅ |
| `SUPABASE_ANON_KEY` | ✅ | ✅ (Secret Manager) | ✅ |
| `CLOUD_RUN_URL` | ❌ | ❌ | ✅ (for fallback) |

---

## 🆘 Troubleshooting URLs

### ตรวจสอบ Logs

```powershell
# Cloud Run
gcloud run logs read nextplot-linebot --limit 50

# Vercel
vercel logs nextplotlinebot

# Local
tail -f storage/logs/laravel.log
```

### ตรวจสอบ Deployments

```powershell
# Cloud Run
gcloud run services describe nextplot-linebot --region asia-southeast1

# Cloud Build
gcloud builds list --limit 5

# Vercel
vercel ls
```

---

## 📞 Support & Documentation

- [README.md](README.md) - คู่มือหลัก
- [DEPLOYMENT.md](DEPLOYMENT.md) - คู่มือ deployment และ failover
- [QUICK_START.md](QUICK_START.md) - เริ่มต้นใช้งาน
- [LINE Developers Documentation](https://developers.line.biz/en/docs/)
- [Google Cloud Run Documentation](https://cloud.google.com/run/docs)
- [Vercel Documentation](https://vercel.com/docs)

---

**อัปเดตล่าสุด:** 20 ตุลาคม 2025  
**สถานะ:** ✅ ทุก service พร้อมใช้งาน
