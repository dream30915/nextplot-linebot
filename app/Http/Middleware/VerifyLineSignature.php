<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

/**
 * Verify LINE Signature Middleware
 * 
 * Validates incoming webhook requests from LINE Platform
 * using HMAC-SHA256 signature verification
 */
class VerifyLineSignature
{
    /**
     * Handle an incoming request.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Closure  $next
     * @return mixed
     */
    public function handle(Request $request, Closure $next)
    {
        // Skip verification if relaxed mode is enabled
        if (config('nextplot.line.signature_relaxed', false)) {
            Log::info('[LINE Signature] Relaxed mode - skipping verification');
            return $next($request);
        }

        // Get signature from header
        $signature = $request->header('x-line-signature');
        if (!$signature) {
            Log::warning('[LINE Signature] Missing signature header');
            return response()->json(['error' => 'Missing signature'], 401);
        }

        // Get raw body
        $body = $request->getContent();
        
        // Get channel secret
        $channelSecret = config('nextplot.line.channel_secret');
        if (!$channelSecret) {
            Log::error('[LINE Signature] Missing channel secret in config');
            return response()->json(['error' => 'Configuration error'], 500);
        }

        // Calculate signature
        $hash = base64_encode(hash_hmac('sha256', $body, $channelSecret, true));

        // Verify signature
        if (!hash_equals($hash, $signature)) {
            Log::warning('[LINE Signature] Invalid signature', [
                'expected' => $hash,
                'received' => $signature,
            ]);
            return response()->json(['error' => 'Invalid signature'], 401);
        }

        Log::info('[LINE Signature] Verification successful');
        return $next($request);
    }
}
