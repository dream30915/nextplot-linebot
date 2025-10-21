/**
 * Health check endpoint for Vercel serverless function
 */

export default async function handler(req, res) {
    try {
        const cloudRunUrl = process.env.CLOUD_RUN_URL;

        const status = {
            status: 'healthy',
            service: 'vercel',
            timestamp: new Date().toISOString(),
            env: {
                CLOUD_RUN_URL: cloudRunUrl ? 'configured' : 'missing',
                LINE_CHANNEL_SECRET: process.env.LINE_CHANNEL_SECRET ? 'configured' : 'missing',
                LINE_CHANNEL_ACCESS_TOKEN: process.env.LINE_CHANNEL_ACCESS_TOKEN ? 'configured' : 'missing',
                SUPABASE_URL: process.env.SUPABASE_URL ? 'configured' : 'missing'
            }
        };

        return res.status(200).json(status);
    } catch (error) {
        return res.status(500).json({
            status: 'unhealthy',
            error: error.message,
            timestamp: new Date().toISOString()
        });
    }
}
