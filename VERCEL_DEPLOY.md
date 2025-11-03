# Deploy LINE Bot Webhook (Proxy + AI) บน Vercel

## ภาพรวม

โปรเจกต์นี้มี serverless function บน Vercel (`api/webhook.js`) สำหรับรับ webhook จาก LINE โดย:

- โหมด Proxy: ถ้ามี `CLOUD_RUN_URL` จะส่งต่อไปยัง Cloud Run (Laravel) ก่อน แล้วคืนค่าที่ได้กลับไปยัง LINE
- โหมด Local AI: ถ้าไม่มี `CLOUD_RUN_URL` (หรือบังคับด้วย `FORCE_LOCAL_AI=true`) จะตอบกลับทันทีด้วย AI โดยใช้ OpenAI และ `@line/bot-sdk`

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

### 3. ตั้งค่า Environment Variables (สำคัญ)

ต้องตั้งค่าต่อไปนี้อย่างน้อย:

- `LINE_CHANNEL_ACCESS_TOKEN` — ค่าจาก LINE Developers
- `LINE_CHANNEL_SECRET` — ค่าจาก LINE Developers
- `OPENAI_API_KEY` — คีย์ของ OpenAI (ใช้กับโหมด Local AI)

ตัวเลือกเพิ่มเติม:

- `CLOUD_RUN_URL` — URL พื้นฐานของบริการ Laravel บน Cloud Run (เช่น `https://your-cloud-run-url.run.app`). ถ้ามีค่านี้จะพยายามส่งต่อก่อน
- `FORCE_LOCAL_AI` — ใส่ `true` เพื่อข้ามการส่งต่อไป Cloud Run และให้ Vercel ตอบด้วย AI ทันที
- `OPENAI_CHAT_MODEL` — ค่าเริ่มต้น `gpt-4o-mini`
- `OPENAI_SYSTEM_PROMPT` — ปรับแต่งบุคลิก/บริบทของผู้ช่วย

#### วิธีที่ 1: ผ่าน CLI

```powershell
vercel env add LINE_CHANNEL_ACCESS_TOKEN
vercel env add LINE_CHANNEL_SECRET
vercel env add OPENAI_API_KEY
# ตัวเลือก
vercel env add CLOUD_RUN_URL
vercel env add FORCE_LOCAL_AI
vercel env add OPENAI_CHAT_MODEL
vercel env add OPENAI_SYSTEM_PROMPT
```

เมื่อถามให้เลือก environment: เลือก **Production, Preview, Development**

#### วิธีที่ 2: ผ่าน Vercel Dashboard

1. ไปที่ <https://vercel.com/dashboard>
2. เลือกโปรเจกต์ของคุณ
3. Settings > Environment Variables
4. เพิ่มตัวแปรเหล่านี้:
   - `LINE_CHANNEL_ACCESS_TOKEN`
   - `LINE_CHANNEL_SECRET`
   - `OPENAI_API_KEY`
   - (ตัวเลือก) `CLOUD_RUN_URL`, `FORCE_LOCAL_AI`, `OPENAI_CHAT_MODEL`, `OPENAI_SYSTEM_PROMPT`

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

### ทดสอบ Webhook

```powershell
# (โหมด Local AI) — กด Test จาก LINE Console ได้ทันทีถ้าตั้งค่า ENV ครบ
# (โหมด Proxy) — ถ้าใช้ Cloud Run ให้ตรวจว่าบริการตอบ 200 ที่ /api/line/webhook
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
vercel env rm CLOUD_RUN_URL production
vercel env add CLOUD_RUN_URL production
# ใส่ค่า: https://abc123.ngrok.io
```

## หมายเหตุ

- **CLOUD_RUN_URL** ต้องเป็น URL ที่ Vercel เข้าถึงได้ (ไม่ใช่ localhost)
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

## Data‑backed Q&A (เชื่อม Cloud Run เพื่อดึงข้อมูลจริง)

ถ้าตั้งค่า `CLOUD_RUN_URL` แล้ว ฟังก์ชันบน Vercel จะพยายามเรียก `GET {CLOUD_RUN_URL}/api/nextplot/aggregates` เพื่อดึงสรุปข้อมูล และตอบคำถามอัตโนมัติ เช่น:

- "พื้นที่รวมกี่ไร่" / "total rai"
- "มีกี่โฉนด" / "deed count"
- "ใครหาเยอะสุด" / "top finder"
- "แปลงล่าสุดเป็นอะไร" / "latest plot"

ถ้า `CLOUD_RUN_URL` ไม่พร้อมใช้งานหรือเรียกไม่สำเร็จ บอทจะ fallback เป็นการตอบด้วย AI ตามปกติ (ไม่ใช้ข้อมูลจริง)

## Troubleshooting

### Error: Missing LINE/OpenAI env

- ตรวจสอบว่า `LINE_CHANNEL_ACCESS_TOKEN`, `LINE_CHANNEL_SECRET`, `OPENAI_API_KEY` ถูกตั้งไว้ครบ
- ดู env ปัจจุบัน: `vercel env ls`
- Deploy ใหม่หลังเพิ่ม env: `vercel --prod`

### Error: Failed to forward webhook (Proxy mode)

- ตรวจสอบว่า Cloud Run URL ถูกต้อง และปลายทางตอบสนอง 200 ที่ `/api/line/webhook`
- ลองตั้ง `FORCE_LOCAL_AI=true` เพื่อทดสอบตอบกลับจาก Vercel โดยตรง

### LINE Webhook verification failed

- บนแพลตฟอร์ม serverless บางกรณี raw body จะไม่ตรงตามที่ LINE ใช้คำนวณลายเซ็นต์ ส่งผลให้ตรวจสอบลายเซ็นต์ล้มเหลวได้
- โค้ดนี้จะบันทึกคำเตือนและยังคงประมวลผลต่อ (best‑effort) เพื่อไม่ให้การตอบกลับล้มเหลว
- ตรวจสอบ `LINE_CHANNEL_SECRET` ให้ถูกต้อง และดู logs: `vercel logs --follow`
