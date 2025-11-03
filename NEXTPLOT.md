# 📘 NextPlot: ระบบจัดการข้อมูลที่ดินผ่าน LINE Bot

## 🎯 เป้าหมาย

ระบบนี้ออกแบบมาเพื่อให้เจ้าของสามารถจัดการข้อมูลที่ดินได้อย่างมืออาชีพผ่าน LINE โดยไม่ต้องใช้คอมพิวเตอร์ และทำงานบน Cloud ทั้งหมด

## 🧩 ฟีเจอร์หลัก

### ✅ ฟีเจอร์ที่ใช้งานได้แล้ว

- ✅ รับข้อความ/รูป/ไฟล์จาก LINE แล้วจัดกลุ่มเป็น "แปลง"
- ✅ บันทึกข้อมูลลง Supabase (PostgreSQL + Storage)
- ✅ ตรวจสอบความครบถ้วนของข้อมูล (CODE, เลขโฉนด)
- ✅ ส่ง Quick Reply เมื่อข้อมูลไม่ครบ
- ✅ อัปโหลดไฟล์และรูปภาพไปยัง Supabase Storage
- ✅ สร้าง Signed URL สำหรับไฟล์ที่เป็นส่วนตัว
- ✅ ตรวจสอบ LINE userId ตาม allowlist

### 🚧 ฟีเจอร์ที่กำลังพัฒนา

- 🚧 จบแปลงเมื่อพิมพ์ "........" หรือไม่มีอินพุตใหม่ใน 10 วินาที
- 🚧 ตั้งชื่อแปลงและไฟล์อัตโนมัติตาม CODE และเลขรัน
- 🚧 แจ้งเตือนผ่าน LINE เมื่อมีแปลงใหม่หรือคำขอส่งออก
- 🚧 ค้นหาข้อมูลด้วยภาษาธรรมชาติ (NLP)
- 🚧 ส่งออกข้อมูลเป็น Excel/CSV/PDF พร้อม Signed URL
- 🚧 OCR สำหรับอ่านเลขโฉนดจากรูปภาพ

## 🧱 โครงสร้างฐานข้อมูล (Supabase)

### ตารางที่มีอยู่

- ✅ `messages`: เก็บข้อความและ events จาก LINE
  - `id` (uuid, PK)
  - `created_at` (timestamptz)
  - `user_id` (text) - LINE userId
  - `event_type` (text) - text, image, file, etc.
  - `text_content` (text) - เนื้อหาข้อความ
  - `raw` (jsonb) - ข้อมูล event เต็มรูปแบบ

### ตารางที่ต้องสร้าง

- 🚧 `members`: ข้อมูลสมาชิก/ผู้ใช้ที่ได้รับอนุญาต
- 🚧 `properties`: ข้อมูลแปลงที่ดิน
- 🚧 `deed_addresses`: ที่อยู่โฉนด
- 🚧 `events`: เหตุการณ์ต่าง ๆ (สร้าง, แก้ไข, ส่งออก)

## 📦 เทคโนโลยีที่ใช้

### Backend Stack

- **Runtime**: Node.js 22 (Vercel Serverless Functions)
- **Database**: Supabase (PostgreSQL)
- **Storage**: Supabase Storage (S3-compatible)
- **API**: LINE Messaging API

### ไลบรารีหลัก

- `node-fetch` - HTTP requests
- Native `crypto` - HMAC signature verification

## 🧠 ตัวอย่างคำสั่งจากผู้ใช้

### ✅ ใช้งานได้แล้ว

- "WC-007 โฉนด 8899" → บันทึกข้อมูล
- [ส่งรูปภาพ] → อัปโหลดและสร้าง signed URL
- "ทดสอบ" → แจ้งว่าข้อมูลไม่ครบ + Quick Reply

### 🚧 กำลังพัฒนา

- "WC-007 โฉนด 8899 เนื้อที่ 3-2-50 ต.พลา อ.บ้านฉาง จ.ระยอง ........"
- "WC มีทั้งหมดกี่ไร่ กี่แปลง"
- "แปลงนี้ใครเป็นคนหามา"
- "แนบสรุป WC Excel"

## 🔐 ความปลอดภัย

### ✅ มาตรการที่เปิดใช้งานแล้ว

- LINE Signature Verification (สามารถปิดได้ด้วย `LINE_SIGNATURE_RELAXED=true`)
- User ID Allowlist - เฉพาะ userId ที่ได้รับอนุญาต
- Supabase RLS (Row Level Security) - กำลังตั้งค่า
- Private Storage Bucket + Signed URL (expiry 1 hour)

### 🚧 มาตรการที่กำลังเพิ่ม

- การอนุมัติก่อนส่งออกข้อมูล
- Audit log สำหรับการเปลี่ยนแปลงข้อมูล
- Rate limiting สำหรับ webhook

## 🚀 การติดตั้งและใช้งาน

### Environment Variables ที่จำเป็น

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

### การ Deploy

```bash
# 1. ติดตั้ง dependencies
npm install

# 2. ตั้งค่า environment variables
vercel env add LINE_CHANNEL_ACCESS_TOKEN production
vercel env add SUPABASE_URL production
# ... (ตั้งค่าตัวแปรอื่น ๆ)

# 3. Deploy ไปยัง production
vercel deploy --prod

# 4. ตั้งค่า LINE Webhook URL
# ไปที่ https://developers.line.biz/console/
# ตั้ง Webhook URL: https://your-domain.vercel.app/api/line/webhook
```

### การทดสอบ

```bash
# ทดสอบ health endpoint
curl https://your-domain.vercel.app/api/health

# ทดสอบ webhook (จำเป็นต้องมี valid LINE signature)
curl -X POST https://your-domain.vercel.app/api/line/webhook \
  -H "Content-Type: application/json" \
  -d '{"events":[{"type":"message","message":{"type":"text","text":"test"}}]}'
```

## 📂 โครงสร้างโปรเจกต์

```
line-webhook-proxy/
├── api/
│   ├── health.js              # Health check endpoint
│   └── line/
│       └── webhook.js         # LINE webhook handler (entry point)
├── lib/
│   ├── nextplot.js           # Business logic (Quick Reply, media handling)
│   └── supabase.js           # Supabase client (insert, upload, sign)
├── public/
│   └── index.html            # Landing page
├── .github/
│   └── instructions/         # Copilot instruction files
├── vercel.json               # Vercel configuration
└── package.json
```

## 🔧 การพัฒนาต่อ

### ขั้นตอนถัดไป

1. ✅ ~~เชื่อมต่อ LINE Webhook กับ Supabase~~ - **เสร็จแล้ว**
2. ✅ ~~ระบบ Quick Reply สำหรับข้อมูลไม่ครบ~~ - **เสร็จแล้ว**
3. 🚧 สร้างตาราง `properties`, `members`, `deed_addresses`
4. 🚧 พัฒนาระบบจบแปลง (session timeout 10 วินาที)
5. 🚧 ระบบตั้งชื่อไฟล์อัตโนมัติตาม CODE
6. 🚧 ระบบแจ้งเตือนผ่าน LINE Push API
7. 🚧 ระบบค้นหาด้วย NLP (Natural Language Processing)
8. 🚧 ระบบส่งออก Excel/PDF พร้อม Signed URL

### วิธีเพิ่มฟีเจอร์ใหม่

1. แก้ไข `lib/nextplot.js` สำหรับ business logic
2. แก้ไข `api/line/webhook.js` ถ้าต้องการเปลี่ยน webhook handling
3. Deploy ด้วย `vercel deploy --prod`

## 📞 Support

- **Issues**: สร้าง Issue ใน GitHub Repository
- **Documentation**: อ่านใน `/how-to-guides/`
- **Copilot Instructions**: ดูใน `/.github/instructions/`

---

**Version**: 1.0.0  
**Last Updated**: 2025-10-19  
**Status**: ✅ Production Ready (Core Features)
