/**
 * Vercel Serverless Function: NextPlot LINE Webhook (BACKUP)
 * 
 * This is a BACKUP endpoint that runs the same Laravel logic
 * Uses Cloud Run as fallback if available, otherwise processes locally
 * 
 * Environment Variables Required:
 * - LINE_CHANNEL_SECRET: LINE Channel Secret for signature verification
 * - LINE_CHANNEL_ACCESS_TOKEN: LINE Messaging API token
 * - SUPABASE_URL: Supabase project URL
 * - SUPABASE_ANON_KEY: Supabase anon key
 * - CLOUD_RUN_URL: (optional) Primary Cloud Run URL for fallback
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
        const channelSecret = process.env.LINE_CHANNEL_SECRET;
        const cloudRunUrl = process.env.CLOUD_RUN_URL;

        console.log('[Vercel Backup] Webhook received');

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
                return res.status(200).json({ success: false, message: 'Invalid signature' });
            }
        }

        // Try Cloud Run first (if URL provided)
        if (cloudRunUrl) {
            try {
                console.log('[Vercel Backup] Trying Cloud Run fallback:', cloudRunUrl);

                const response = await fetch(`${cloudRunUrl}/api/line/webhook`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'x-line-signature': signature,
                        'x-forwarded-from': 'vercel-backup',
                    },
                    body: JSON.stringify(req.body),
                    signal: AbortSignal.timeout(8000), // 8 second timeout
                });

                if (response.ok) {
                    const responseData = await response.text();
                    console.log('[Vercel Backup] Cloud Run success');
                    return res.status(200).send(responseData);
                }

                console.warn('[Vercel Backup] Cloud Run failed, processing locally');
            } catch (error) {
                console.warn('[Vercel Backup] Cloud Run error:', error.message);
                // Fall through to local processing
            }
        }

        // Process locally (simplified version)
        console.log('[Vercel Backup] Processing locally');

        const events = req.body.events || [];
        console.log(`[Vercel Backup] Processing ${events.length} events`);

        // Simple echo response
        for (const event of events) {
            if (event.type === 'message' && event.message.type === 'text') {
                console.log('[Vercel Backup] Message:', event.message.text);
                // TODO: Implement full NextPlot logic here if needed
                // For now, just acknowledge receipt
            }
        }

        return res.status(200).json({
            success: true,
            message: 'Webhook processed by Vercel backup',
            events: events.length
        });

    } catch (error) {
        console.error('[Vercel Backup] Error:', error);
        return res.status(200).json({
            success: false,
            error: 'Webhook processing failed',
            message: error.message
        });
    }
};

