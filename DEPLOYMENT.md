# DEPLOYMENT.md

เอกสารแนะนำการ deploy และการจัดการ NextPlot LINE Bot

## สรุปสถาปัตยกรรม

- Primary: Google Cloud Run
  - URL: <https://nextplot-linebot-656d4rnjja-as.a.run.app>
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
   - PowerShell: `. est-all.ps1`
2. เปลี่ยน webhook เป็น Cloud Run (production):
   - PowerShell: `.\
switch-webhook.ps1 -Target cloudrun`
3. เปลี่ยน webhook เป็น Vercel (fallback):
   - PowerShell: `.
switch-webhook.ps1 -Target vercel`

## ข้อควรระวัง

- LINE Webhook ยอมให้ตั้งได้แค่ 1 URL เท่านั้น
- การสลับ webhook อาจทำให้มี downtime เล็กน้อย (ไม่กี่วินาที)
- เก็บ `.env` ให้ปลอดภัย ห้าม commit keys ลง Git

## ขั้นตอนแนะนำเมื่อ Cloud Run down

1. ตรวจสอบ `test-all.ps1` เพื่อหาสาเหตุ
2. ถ้ายืนยัน Cloud Run down ให้รัน:
   - `.
switch-webhook.ps1 -Target vercel`
3. ตรวจสอบว่า webhook ถูกสลับแล้วโดยเช็ค `.
switch-webhook.ps1 -Target status` หรือดูใน LINE Developers Console

## ข้อเสนอแนะเพิ่มเติม

- ตั้งการมอนิเตอร์ uptime (UptimeRobot หรือ Cloud Monitoring)
- สร้าง runbook สั้นๆ สำหรับการติดต่อและการแก้ไขที่รวดเร็ว
