# DEPLOYMENT.md

เอกสารแนะนำการ deploy และการจัดการ NextPlot LINE Bot

## สรุปสถาปัตยกรรม

- Primary: Google Cloud Run
  - URL: <https://nextplot-linebot-546634969975.asia-southeast1.run.app>
  - เหมาะสำหรับ production, รองรับ 2M requests/month (free tier)
- Backup: Vercel
  - URL (ตัวอย่าง): <https://nextplotlinebot.vercel.app>
  - ทำหน้าที่เป็น standby webhook proxy/backup
- Storage: Supabase (bucket: nextplot)
- Dev Tunnel: Cloudflared (ใช้สำหรับ development เท่านั้น)

## ไฟล์สำคัญ

- `.env` - ค่าคอนฟิกทั้งหมด (LINE token, Supabase keys)
- `switch-webhook.ps1` - สคริปต์สำหรับสลับ webhook ระหว่าง cloudrun / vercel
- `test-all.ps1` - สคริปต์ทดสอบครบวงจร (8 tests)
- `api/webhook.js` - Vercel serverless function เป็น backup
- `vercel.json` - การตั้งค่า Vercel deploy

## วิธีใช้งานหลัก

1. ตรวจสอบสถานะ (ในเครื่อง):
   - PowerShell:

     ```powershell
     .\test-all.ps1
     ```

2. เปลี่ยน webhook เป็น Cloud Run (production):
   - PowerShell:

     ```powershell
     .\switch-webhook.ps1 -Target cloudrun
     ```

3. เปลี่ยน webhook เป็น Vercel (fallback):
   - PowerShell:

     ```powershell
     .\switch-webhook.ps1 -Target vercel
     ```


## 📌 Session & Auto-Naming (Quick Examples)

### Session Management

- เริ่ม session ใหม่เมื่อพิมพ์ `........` หรือไม่มีข้อความใหม่เกิน 10 วินาที
- ระบบบันทึก `session_id` และ `last_activity_at` เพื่อผูกกับสื่อและบันทึกการสนทนา

### Media Auto-Naming

- ชื่อไฟล์: `{CODE}-{RUN}_{messageId}.{ext}`
- ไม่มี CODE: `S{RUN}_{messageId}.{ext}`
- เส้นทางเก็บ (ตัวอย่าง): `line/YYYY/MM/DD/<filename>`

## 🧾 Supabase Schema Deployment

สคริปต์: `scripts/deploy-supabase-schema.ps1`  
สคีมา: `supabase/schema.sql`

ข้อกำหนด:

- ติดตั้ง `psql` ใน PATH
- ตั้งค่า `SUPABASE_DB_URL` ใน `.env` หรือส่ง `-DatabaseUrl`

ตั้งค่า SUPABASE_DB_URL อย่างเร็ว (ตัวช่วย):

```powershell
./scripts/make-supabase-db-url.ps1 -DbPassword "<YOUR_DB_PASSWORD>"
```

รันแบบ Dry-run (ไม่เขียนจริง):

```powershell
./scripts/deploy-supabase-schema.ps1 -DryRun
```

Apply จริง (แก้ฐานข้อมูล):

```powershell
./scripts/deploy-supabase-schema.ps1 -Apply
```

ส่ง URL ตรง ๆ (ถ้าไม่ได้ตั้งใน .env):

```powershell
./scripts/deploy-supabase-schema.ps1 -DryRun -DatabaseUrl "postgresql://postgres:<PWD>@db.<REF>.supabase.co:5432/postgres?sslmode=require"
```

## ข้อควรระวัง

- LINE Webhook ยอมให้ตั้งได้แค่ 1 URL เท่านั้น
- การสลับ webhook อาจทำให้มี downtime เล็กน้อย (ไม่กี่วินาที)
- เก็บ `.env` ให้ปลอดภัย ห้าม commit keys ลง Git

## ขั้นตอนแนะนำเมื่อ Cloud Run down

1. ตรวจสอบ `test-all.ps1` เพื่อหาสาเหตุ
1. ถ้ายืนยัน Cloud Run down ให้รัน:

  ```powershell
  .\switch-webhook.ps1 -Target vercel
  ```

1. ตรวจสอบว่า webhook ถูกสลับแล้วโดยเช็ค:

  ```powershell
  .\switch-webhook.ps1 -Target status
  ```
  
   หรือดูใน LINE Developers Console


## ข้อเสนอแนะเพิ่มเติม

- ตั้งการมอนิเตอร์ uptime (UptimeRobot หรือ Cloud Monitoring)
- สร้าง runbook สั้นๆ สำหรับการติดต่อและการแก้ไขที่รวดเร็ว
