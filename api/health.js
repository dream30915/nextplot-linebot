/**
 * Health check endpoint for Vercel function
 */

export default async function handler(req, res) {
    try {
        const laravelUrl = process.env.LARAVEL_URL;

        const status = {
            vercel: 'ok',
            timestamp: new Date().toISOString(),
            env: {
                LARAVEL_URL: laravelUrl ? 'configured' : 'missing',
                LINE_CHANNEL_SECRET: process.env.LINE_CHANNEL_SECRET ? 'configured' : 'missing'
            }
        };

        return res.status(200).json(status);
    } catch (error) {
        return res.status(500).json({
            error: 'Internal server error',
            message: error.message
        });
    }
}
