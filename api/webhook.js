/**
 * Vercel Serverless Function: LINE Webhook Proxy
 * 
 * This function receives webhook events from LINE Platform
 * and forwards them to your local Laravel application.
 * 
 * Environment Variables Required:
 * - LARAVEL_URL: Your Laravel app URL (e.g., http://localhost:8000 or ngrok URL)
 * - LINE_CHANNEL_SECRET: LINE Channel Secret for signature verification
 */

import crypto from 'crypto';

/**
 * Verify LINE signature
 */
function verifySignature(body, signature, secret) {
    const hash = crypto
        .createHmac('sha256', secret)
        .update(body)
        .digest('base64');
    return hash === signature;
}

/**
 * Main handler
 */
export default async function handler(req, res) {
    // Only accept POST requests
    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'Method not allowed' });
    }

    try {
        const laravelUrl = process.env.LARAVEL_URL;
        const channelSecret = process.env.LINE_CHANNEL_SECRET;

        // 🔥 สำหรับ LINE webhook verification - return 200 ทันที
        if (!laravelUrl) {
            console.log('LARAVEL_URL not configured - responding 200 for LINE verification');
            return res.status(200).json({ success: true, message: 'Webhook received' });
        }

        // Verify LINE signature
        const signature = req.headers['x-line-signature'];
        if (!signature) {
            console.warn('Missing x-line-signature header');
            return res.status(200).json({ success: true, message: 'No signature provided' });
        }

        if (channelSecret) {
            const body = JSON.stringify(req.body);
            if (!verifySignature(body, signature, channelSecret)) {
                console.warn('Invalid signature');
                // ⚠️ ยังคืน 200 เพื่อให้ LINE verification ผ่าน
                return res.status(200).json({ success: false, message: 'Invalid signature' });
            }
        }

        // Forward to Laravel
        console.log('Forwarding webhook to Laravel:', laravelUrl);

        const response = await fetch(`${laravelUrl}/api/line/webhook`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'x-line-signature': signature,
                'x-forwarded-from': 'vercel',
            },
            body: JSON.stringify(req.body),
        });

        const responseData = await response.text();

        console.log('Laravel response:', {
            status: response.status,
            body: responseData.substring(0, 200),
        });

        // Return Laravel's response
        return res.status(response.ok ? 200 : 500).send(responseData);

    } catch (error) {
        console.error('Webhook proxy error:', error);
        // ⚠️ ยังคืน 200 เพื่อไม่ให้ LINE retry ซ้ำ
        return res.status(200).json({
            success: false,
            error: 'Failed to forward webhook',
            message: error.message
        });
    }
};
