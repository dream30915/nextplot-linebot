# Deploy LINE Bot Webhook Proxy บน Vercel

## ภาพรวม

โปรเจกต์นี้มี serverless functions บน Vercel ที่ทำหน้าที่เป็น proxy รับ webhook จาก LINE แล้วส่งต่อมาที่ Laravel app ที่รันบนเครื่องคุณ

## ขั้นตอนการ Deploy

### 1. เตรียม Vercel CLI

```powershell
npm install -g vercel
vercel login
```

### 2. Deploy ครั้งแรก

```powershell
# ใน directory โปรเจกต์นี้
vercel
```

ตอบคำถาม:

- Set up and deploy? `Y`
- Which scope? เลือกบัญชีของคุณ
- Link to existing project? `N`
- Project name? `nextplot-linebot-proxy` (หรือชื่ออื่น)
- Directory? `.` (ใช้ directory ปัจจุบัน)

### 3. ตั้งค่า Environment Variables

#### วิธีที่ 1: ผ่าน CLI

```powershell
# ตั้งค่า Laravel URL (ใช้ ngrok, localtunnel หรือ public IP)
vercel env add LARAVEL_URL

# ตั้งค่า LINE Channel Secret
vercel env add LINE_CHANNEL_SECRET
```

เมื่อถามให้เลือก environment: เลือก **Production, Preview, Development**

#### วิธีที่ 2: ผ่าน Vercel Dashboard

1. ไปที่ <https://vercel.com/dashboard>
2. เลือกโปรเจกต์ของคุณ
3. Settings > Environment Variables
4. เพิ่มตัวแปรเหล่านี้:
   - `LARAVEL_URL` = `http://your-tunnel-url` (เช่น `https://abc123.ngrok.io`)
   - `LINE_CHANNEL_SECRET` = ค่าจาก LINE Developers

### 4. Deploy Production

```powershell
vercel --prod
```

คุณจะได้ URL แบบ: `https://nextplot-linebot-proxy.vercel.app`

### 5. ตั้งค่า LINE Webhook URL

1. ไปที่ LINE Developers Console
2. เลือก Messaging API channel ของคุณ
3. ไปที่ **Messaging API** > **Webhook settings**
4. ตั้ง Webhook URL เป็น:

   ```
   https://your-vercel-app.vercel.app/api/webhook
   ```

5. กด **Verify** และ **Use webhook**

## การทดสอบ

### ทดสอบ Health Check

```powershell
Invoke-WebRequest -Uri "https://your-vercel-app.vercel.app/api/health"
```

### ทดสอบ Webhook (ต้องเปิด Laravel serve ก่อน)

```powershell
# เริ่ม Laravel
php artisan serve

# ทดสอบส่ง webhook จาก LINE
# ไปที่ LINE Console > Messaging API > Webhook settings > Test
```

## วิธีใช้กับ ngrok แทน Cloudflare

### ติดตั้ง ngrok

```powershell
# ดาวน์โหลดจาก https://ngrok.com/download
# หรือใช้ chocolatey
choco install ngrok
```

### รัน ngrok

```powershell
# เปิด tunnel ไปที่ Laravel
ngrok http 8000
```

คุณจะได้ URL เช่น `https://abc123.ngrok.io`

### อัปเดต Vercel env

```powershell
vercel env rm LARAVEL_URL production
vercel env add LARAVEL_URL production
# ใส่ค่า: https://abc123.ngrok.io
```

## หมายเหตุ

- **LARAVEL_URL** ต้องเป็น URL ที่ Vercel เข้าถึงได้ (ไม่ใช่ localhost)
- ถ้าใช้ ngrok free tier URL จะเปลี่ยนทุกครั้งที่รีสตาร์ท ต้องอัปเดต env ใหม่
- Vercel functions มี timeout 10 วินาที (free tier) หรือ 60 วินาที (Pro)

## คำสั่งที่เป็นประโยชน์

```powershell
# ดู logs แบบ real-time
vercel logs --follow

# ดู environment variables
vercel env ls

# ลบและ deploy ใหม่
vercel --prod --force
```

## Troubleshooting

### Error: LARAVEL_URL not configured

- ตรวจสอบว่าตั้งค่า env variable แล้ว: `vercel env ls`
- Deploy ใหม่หลังเพิ่ม env: `vercel --prod`

### Error: Failed to forward webhook

- ตรวจสอบว่า Laravel รันอยู่: `php artisan serve`
- ตรวจสอบว่า ngrok/tunnel ยังทำงานอยู่
- ทดสอบ health check: `/api/health`

### LINE Webhook verification failed

- ตรวจสอบ `LINE_CHANNEL_SECRET` ถูกต้อง
- ดู logs: `vercel logs --follow`
