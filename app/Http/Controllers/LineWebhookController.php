<?php

namespace App\Http\Controllers;

use App\Services\NextPlotService;
use App\Services\SupabaseService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * LINE Webhook Controller
 * Translated from: line-webhook-proxy/api/line/webhook.js
 * 
 * Handles LINE webhook events:
 * - Verify LINE signature (HMAC-SHA256)
 * - Process events with NextPlotService
 * - Send reply messages back to LINE
 */
class LineWebhookController extends Controller
{
    private ?NextPlotService $nextPlot;
    private ?SupabaseService $supabase;
    private string $channelSecret;
    private string $accessToken;
    private bool $signatureRelaxed;
    private array $allowlist;

    public function __construct(?NextPlotService $nextPlot = null, ?SupabaseService $supabase = null)
    {
        // Allow graceful degradation for debugging
        try {
            $this->nextPlot = $nextPlot ?? app(NextPlotService::class);
            $this->supabase = $supabase ?? app(SupabaseService::class);
        } catch (\Exception $e) {
            Log::error('[LINE Webhook] Service initialization failed', [
                'error' => $e->getMessage(),
            ]);
            $this->nextPlot = null;
            $this->supabase = null;
        }
        
        $this->channelSecret = config('nextplot.line.channel_secret');
        $this->accessToken = config('nextplot.line.access_token');
        $this->signatureRelaxed = config('nextplot.line.signature_relaxed', false);
        $this->allowlist = explode(',', config('nextplot.line.user_id_allowlist', ''));
    }

    /**
     * Handle LINE webhook POST request
     */
    public function handle(Request $request)
    {
        try {
            Log::info('[LINE Webhook] Request received', [
                'method' => $request->method(),
                'url' => $request->fullUrl(),
                'has_signature' => $request->hasHeader('x-line-signature'),
            ]);

            // RELAX MODE: Return 200 OK immediately for debugging
            if (env('LINE_WEBHOOK_RELAX_VERIFY', false)) {
                Log::info('[LINE Webhook] RELAX MODE: Returning 200 OK');
                return response()->json(['ok' => true, 'mode' => 'relax']);
            }

            // Check if services are initialized
            if (!$this->nextPlot || !$this->supabase) {
                Log::error('[LINE Webhook] Services not initialized');
                return response()->json(['error' => 'Services not initialized'], 500);
            }

            // Verify signature
            if (!$this->signatureRelaxed) {
                $signature = $request->header('x-line-signature');
                if (!$signature) {
                    Log::warning('[LINE Webhook] Missing signature');
                    return response()->json(['error' => 'Missing signature'], 401);
                }

                $body = $request->getContent();
                if (!$this->verifySignature($body, $signature)) {
                    Log::warning('[LINE Webhook] Invalid signature');
                    return response()->json(['error' => 'Invalid signature'], 401);
                }
            }

            // Parse body
            $body = $request->json()->all();
            $events = $body['events'] ?? [];

            Log::info('[LINE Webhook] Events received', [
                'count' => count($events),
            ]);

            // Process each event
            foreach ($events as $event) {
                $this->processEvent($event);
            }

            return response()->json(['ok' => true]);

        } catch (\Throwable $e) {
            Log::error('[LINE Webhook] Unhandled error', [
                'error' => $e->getMessage(),
                'file' => $e->getFile(),
                'line' => $e->getLine(),
                'trace' => $e->getTraceAsString(),
            ]);
            
            // Return 200 to prevent LINE from retrying during debugging
            if (env('APP_DEBUG', false)) {
                return response()->json([
                    'ok' => false,
                    'error' => $e->getMessage(),
                    'debug' => true
                ], 200);
            }
            
            return response()->json(['error' => 'Internal server error'], 500);
        }
    }

    /**
     * Process a single event
     */
    private function processEvent(array $event): void
    {
        try {
            $eventType = $event['type'] ?? '';
            $userId = $event['source']['userId'] ?? 'unknown';
            $replyToken = $event['replyToken'] ?? null;

            Log::info('[LINE Webhook] Processing event', [
                'type' => $eventType,
                'userId' => $userId,
            ]);

            // Check allowlist
            if (!empty($this->allowlist) && !in_array($userId, $this->allowlist)) {
                Log::warning('[LINE Webhook] User not in allowlist', ['userId' => $userId]);
                return;
            }

            // Save to database (simple version)
            if ($eventType === 'message') {
                $message = $event['message'] ?? [];
                $this->supabase->insertRow('messages', [
                    'user_id' => $userId,
                    'event_type' => $message['type'] ?? 'unknown',
                    'text_content' => $message['text'] ?? null,
                    'raw' => $event,
                ]);
            }

            // Process with NextPlotService
            $replyMessage = $this->nextPlot->processEvent($event);

            // Send reply if available
            if ($replyMessage && $replyToken) {
                $this->sendReply($replyToken, $replyMessage);
            }

        } catch (\Exception $e) {
            Log::error('[LINE Webhook] Event processing error', [
                'event' => $event,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * Verify LINE signature using HMAC-SHA256
     */
    private function verifySignature(string $body, string $signature): bool
    {
        $hash = base64_encode(hash_hmac('sha256', $body, $this->channelSecret, true));
        return hash_equals($hash, $signature);
    }

    /**
     * Send reply message to LINE
     */
    private function sendReply(string $replyToken, array $message): void
    {
        try {
            $url = 'https://api.line.me/v2/bot/message/reply';
            
            $response = Http::withHeaders([
                'Authorization' => "Bearer {$this->accessToken}",
                'Content-Type' => 'application/json',
            ])->post($url, [
                'replyToken' => $replyToken,
                'messages' => [$message],
            ]);

            if ($response->successful()) {
                Log::info('[LINE Webhook] Reply sent', [
                    'replyToken' => $replyToken,
                    'message' => $message,
                ]);
            } else {
                Log::error('[LINE Webhook] Reply failed', [
                    'replyToken' => $replyToken,
                    'status' => $response->status(),
                    'body' => $response->body(),
                ]);
            }

        } catch (\Exception $e) {
            Log::error('[LINE Webhook] Reply error', [
                'replyToken' => $replyToken,
                'error' => $e->getMessage(),
            ]);
        }
    }
}
