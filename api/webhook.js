/**
 * Vercel Serverless Function: NextPlot LINE Webhook with AI layer
 *
 * Behaviour:
 * - If CLOUD_RUN_URL exists and FORCE_LOCAL_AI !== 'true', forward to Cloud Run first, fallback to local.
 * - Otherwise, process locally with @line/bot-sdk + OpenAI.
 *
 * Env Vars:
 * - LINE_CHANNEL_SECRET, LINE_CHANNEL_ACCESS_TOKEN
 * - OPENAI_API_KEY, OPENAI_CHAT_MODEL (default: gpt-4o-mini), OPENAI_SYSTEM_PROMPT (optional)
 * - CLOUD_RUN_URL (optional), FORCE_LOCAL_AI (optional: 'true' to always process locally)
 */

import crypto from 'crypto';
import { Client as LineClient } from '@line/bot-sdk';
import OpenAI from 'openai';

// Verify LINE signature
function verifySignature(body, signature, secret) {
    const hash = crypto.createHmac('sha256', secret).update(body).digest('base64');
    return hash === signature;
}

// Detect data Q&A intents
function detectAggregateIntent(text) {
    const t = String(text || '').toLowerCase();
    // Thai + simple English fallbacks
    if (t.includes('กี่ไร') || t.includes('รวมกี่ไร') || t.includes('total rai') || t.includes('พื้นที่รวม')) {
        return 'total_rai';
    }
    if (t.includes('กี่โฉนด') || t.includes('โฉนดกี่') || t.includes('deed count')) {
        return 'deed_count';
    }
    if (t.includes('ใครหา') || t.includes('top finder') || t.includes('ใครแนะนำ')) {
        return 'top_finder';
    }
    if (t.includes('แปลงล่าสุด') || t.includes('ล่าสุด') || t.includes('latest plot')) {
        return 'latest_plot';
    }
    return null;
}

const ZERO_WIDTH_REGEX = /[\u200B-\u200D\uFEFF]/g;
const CONTROL_REGEX = /[\u0000-\u001F\u007F]/g;
const AREA_REGEX = /^มีที่\s*(.+?)\s*(?:ไหม|มั้ย)\??$/;

function sanitizeText(text) {
    if (typeof text !== 'string') {
        return '';
    }
    return text
        .replace(ZERO_WIDTH_REGEX, '')
        .replace(CONTROL_REGEX, '')
        .trim();
}

function normalizeCommandKey(text) {
    return sanitizeText(text).toLowerCase().replace(/\s+/g, '');
}

async function fetchAggregates(baseUrl) {
    const url = `${baseUrl.replace(/\/$/, '')}/api/nextplot/aggregates`;
    const resp = await fetch(url, { method: 'GET', headers: { 'accept': 'application/json' }, signal: AbortSignal.timeout(5000) });
    if (!resp.ok) throw new Error(`aggregates http ${resp.status}`);
    return resp.json();
}

// Local AI processing
async function processLocallyWithAI(req, res) {
    const accessToken = process.env.LINE_CHANNEL_ACCESS_TOKEN;
    const secret = process.env.LINE_CHANNEL_SECRET;
    const openaiKey = process.env.OPENAI_API_KEY;

    if (!accessToken || !secret) {
        console.warn('[Vercel AI] Missing LINE credentials');
    }
    if (!openaiKey) {
        console.warn('[Vercel AI] Missing OPENAI_API_KEY');
    }

    const client = new LineClient({ channelAccessToken: accessToken, channelSecret: secret });
    const openai = new OpenAI({ apiKey: openaiKey });

    const model = process.env.OPENAI_CHAT_MODEL || 'gpt-4o-mini';
    const systemPrompt =
        process.env.OPENAI_SYSTEM_PROMPT ||
        'คุณคือผู้ช่วย NextPlot Assistant พูดไทยได้ เป็นมิตร กระชับ และซื่อสัตย์ ห้ามเดา หากไม่มีข้อมูลให้ตอบว่า "ยังไม่มีข้อมูลในระบบ"';

    const events = Array.isArray(req.body?.events) ? req.body.events : [];
    console.log(`[Vercel AI] Local processing ${events.length} event(s)`);

    for (const event of events) {
        try {
            if (event.type === 'message' && event.message?.type === 'text') {
                const userTextRaw = String(event.message.text ?? '').slice(0, 2000);
                const userText = sanitizeText(userTextRaw);
                const normalized = userText.toLowerCase();
                const commandKey = normalizeCommandKey(userTextRaw);

                // Quick util: whoami/id -> reply LINE userId
                const whoCmds = new Set(['id', 'id?', 'whoami', 'whoami?', 'userid', 'ไอดี', 'ไอดี?']);
                if (whoCmds.has(commandKey)) {
                    const uid = event?.source?.userId || 'unknown';
                    const lines = [
                        'นี่คือ LINE userId ของคุณ:',
                        uid,
                        '',
                        'นำค่านี้ไปตั้งค่าใน .env:',
                        `NEXTPLOT_OWNER_LINE_USER_IDS="${uid}"`,
                    ];
                    await client.replyMessage(event.replyToken, { type: 'text', text: lines.join('\n') });
                    continue;
                }

                // Simple area intent: "มีที่ <พื้นที่> ไหม"
                const areaMatch = normalized.match(AREA_REGEX);
                if (areaMatch) {
                    const where = areaMatch[1];
                    const cloudRunUrl = process.env.CLOUD_RUN_URL;
                    try {
                        if (cloudRunUrl) {
                            const url = `${cloudRunUrl.replace(/\/$/, '')}/api/nextplot/properties/search?text=${encodeURIComponent(where)}`;
                            const resp = await fetch(url, { method: 'GET', headers: { 'accept': 'application/json' }, signal: AbortSignal.timeout(5000) });
                            if (!resp.ok) throw new Error(`search http ${resp.status}`);
                            const data = await resp.json();
                            const n = data?.count ?? 0;
                            if (n > 0) {
                                const items = Array.isArray(data?.items) ? data.items.slice(0, 3) : [];
                                const lines = [`พบที่ดินตรงกับ "${where}" จำนวน ${n} แปลง`];
                                if (items.length > 0) {
                                    lines.push('ตัวอย่าง:');
                                    for (const it of items) {
                                        const code = it?.code || it?.id || '-';
                                        const deed = it?.deed_number ? ` โฉนด:${it.deed_number}` : '';
                                        const loc = [it?.province, it?.district, it?.subdistrict].filter(Boolean).join(' ');
                                        lines.push(`• ${code}${deed}${loc ? ` (${loc})` : ''}`);
                                    }
                                }
                                await client.replyMessage(event.replyToken, { type: 'text', text: lines.join('\n') });
                            } else {
                                await client.replyMessage(event.replyToken, { type: 'text', text: `ยังไม่พบข้อมูลที่ตรงกับ "${where}"` });
                            }
                        } else {
                            await client.replyMessage(event.replyToken, { type: 'text', text: 'ตอนนี้ยังไม่ได้เชื่อม Cloud Run aggregates จึงตอบตามพื้นที่ไม่ได้' });
                        }
                    } catch (e) {
                        await client.replyMessage(event.replyToken, { type: 'text', text: 'ยังไม่มีข้อมูลหรือไม่สามารถสอบถามฐานข้อมูลได้ในขณะนี้' });
                    }
                    continue;
                }

                let aiReply = null;

                // Data-backed Q&A via Cloud Run aggregates when available
                const cloudRunUrl = process.env.CLOUD_RUN_URL;
                const aggIntent = detectAggregateIntent(userText);
                if (aggIntent && cloudRunUrl) {
                    try {
                        const agg = await fetchAggregates(cloudRunUrl);
                        if (agg && agg.ok) {
                            if (aggIntent === 'total_rai') {
                                const rai = agg.total?.rai ?? 0;
                                aiReply = `รวมทั้งหมดประมาณ ${rai} ไร่`;
                            } else if (aggIntent === 'deed_count') {
                                const n = agg.counts?.deeds ?? 0;
                                aiReply = `มีโฉนดทั้งหมด ${n} รายการ`;
                            } else if (aggIntent === 'top_finder') {
                                const name = agg.top_finder?.name || 'ไม่ทราบ';
                                const c = agg.top_finder?.count ?? 0;
                                aiReply = `ผู้แนะนำ/ผู้หาอันดับหนึ่ง: ${name} (${c} แปลง)`;
                            } else if (aggIntent === 'latest_plot') {
                                const lp = agg.latest_plot;
                                if (lp) {
                                    const code = lp.code || lp.id;
                                    const deed = lp.deed_number ? `, โฉนด: ${lp.deed_number}` : '';
                                    const loc = [lp.province, lp.district].filter(Boolean).join(' ');
                                    const when = lp.finalized_at || lp.created_at || '';
                                    aiReply = `แปลงล่าสุด: ${code}${deed}${loc ? `, ${loc}` : ''}${when ? `\nเวลา: ${when}` : ''}`;
                                } else {
                                    aiReply = 'ยังไม่พบแปลงล่าสุด';
                                }
                            }
                        }
                    } catch (e) {
                        console.warn('[Vercel AI] aggregates fetch failed:', e?.message || e);
                    }
                }
                if (!aiReply && openaiKey) {
                    try {
                        const completion = await openai.chat.completions.create({
                            model,
                            temperature: 0.4,
                            max_tokens: 300,
                            messages: [
                                { role: 'system', content: systemPrompt },
                                { role: 'user', content: userTextRaw },
                            ],
                        });
                        aiReply = completion?.choices?.[0]?.message?.content?.slice(0, 1800) || null;
                    } catch (e) {
                        console.warn('[Vercel AI] OpenAI error:', e?.message || e);
                    }
                }

                const text = aiReply || 'ยังไม่มีข้อมูลในระบบ';
                await client.replyMessage(event.replyToken, { type: 'text', text });
            } else if (event.type === 'message') {
                // Non-text messages: acknowledge briefly
                await client.replyMessage(event.replyToken, {
                    type: 'text',
                    text: 'ได้รับข้อความแล้วครับ/ค่ะ (รองรับข้อความตัวอักษรเป็นหลัก)',
                });
            }
        } catch (err) {
            console.error('[Vercel AI] Event handling error:', err);
        }
    }

    return res.status(200).json({ ok: true, mode: 'local-ai', events: events.length });
}

export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).send('Method Not Allowed');
    }

    try {
        const signature = req.headers['x-line-signature'];
        const secret = process.env.LINE_CHANNEL_SECRET;
        const cloudRunUrl = process.env.CLOUD_RUN_URL;
        const forceLocal = String(process.env.FORCE_LOCAL_AI || '').toLowerCase() === 'true';
        const events = Array.isArray(req.body?.events) ? req.body.events : [];

        if (!signature) {
            console.warn('[Vercel AI] Missing x-line-signature');
            return res.status(200).json({ ok: true, warn: 'no-signature' });
        }

        // Verify signature when secret available (best-effort on Vercel JSON body)
        if (secret) {
            try {
                const rawBody = JSON.stringify(req.body || {});
                if (!verifySignature(rawBody, signature, secret)) {
                    // On some platforms we can't access the exact raw body; don't hard-fail.
                    console.warn('[Vercel AI] Signature check failed; proceeding (best-effort mode)');
                }
            } catch (e) {
                console.warn('[Vercel AI] Signature check error; proceeding:', e?.message || e);
            }
        }

        // If any event matches local intents (id/whoami or "มีที่ ... ไหม"), handle locally first
        const hasLocalIntent = events.some(ev => {
            if (ev?.type !== 'message' || ev?.message?.type !== 'text') return false;
            const key = normalizeCommandKey(ev.message.text || '');
            const who = new Set(['id','id?','whoami','whoami?','userid','ไอดี','ไอดี?']);
            if (who.has(key)) return true;
            const normalized = sanitizeText(ev.message.text || '').toLowerCase();
            return AREA_REGEX.test(normalized);
        });
        if (hasLocalIntent) {
            return await processLocallyWithAI(req, res);
        }

        // Prefer Cloud Run unless forced to local, then fallback to local AI
        if (cloudRunUrl && !forceLocal) {
            try {
                console.log('[Vercel AI] Forwarding to Cloud Run:', cloudRunUrl);
                const response = await fetch(`${cloudRunUrl}/api/line/webhook`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'x-line-signature': signature,
                        'x-forwarded-from': 'vercel-ai',
                    },
                    body: JSON.stringify(req.body),
                    signal: AbortSignal.timeout(8000),
                });

                if (response.ok) {
                    const text = await response.text();
                    return res.status(200).send(text);
                }

                console.warn('[Vercel AI] Cloud Run returned non-OK, fallback to local AI');
            } catch (e) {
                console.warn('[Vercel AI] Cloud Run error, fallback to local AI:', e?.message || e);
            }
        }

        // Local AI processing
        return await processLocallyWithAI(req, res);
    } catch (error) {
        console.error('[Vercel AI] Unhandled error:', error);
        // Return 200 to prevent LINE retry storms
        return res.status(200).json({ ok: false, error: 'exception', message: error?.message || String(error) });
    }
}

