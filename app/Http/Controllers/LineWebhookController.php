<?php

namespace App\Http\Controllers;

use App\Services\NextPlotService;
use App\Services\SupabaseSqlClient;
use App\Services\SupabaseService;
use Illuminate\Http\JsonResponse;
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
    private bool $alwaysAck;
    /** @var array<int, string> */
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

        $this->channelSecret    = config('nextplot.line.channel_secret');
        $this->accessToken      = config('nextplot.line.access_token');
    $this->signatureRelaxed = config('nextplot.line.signature_relaxed', false);
    // Safe mode: always acknowledge with 200 OK and never 401/500 (best-effort process and log)
    $this->alwaysAck        = (bool) env('LINE_WEBHOOK_ALWAYS_200', false);

        // Normalize allowlist: support empty env and remove empty/whitespace items
        $allowlistRaw = trim((string) config('nextplot.line.user_id_allowlist', ''));
        $allowlistArr = array_map('trim', explode(',', $allowlistRaw));
        $allowlistArr = array_values(array_filter($allowlistArr, function ($v) {
            return $v !== '' && $v !== null;
        }));
        $this->allowlist = $allowlistArr;
    }

    /**
     * Handle LINE webhook POST request
     */
    public function handle(Request $request): JsonResponse
    {
        try {
            Log::info('[LINE Webhook] Request received', [
                'method'        => $request->method(),
                'url'           => $request->fullUrl(),
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

            // Verify signature (unless relaxed or in always-ack safe mode)
            if (!$this->signatureRelaxed && !$this->alwaysAck) {
                $signature = $request->header('x-line-signature');
                if (!is_string($signature) || $signature === '') {
                    Log::warning('[LINE Webhook] Missing signature');
                    return response()->json(['error' => 'Missing signature'], 401);
                }

                $body = $request->getContent();
                if (!$this->verifySignature($body, $signature)) {
                    Log::warning('[LINE Webhook] Invalid signature');
                    return response()->json(['error' => 'Invalid signature'], 401);
                }
            } else if ($this->alwaysAck) {
                // In safe mode, skip signature validation but record a warning for observability
                if (!$request->hasHeader('x-line-signature')) {
                    Log::warning('[LINE Webhook] Safe mode: skipping signature check (missing)');
                }
            }

            // Parse body
            $body   = $request->json()->all();
            $events = $body['events'] ?? [];

            Log::info('[LINE Webhook] Events received', [
                'count' => count($events),
            ]);

            // Process each event
            foreach ($events as $event) {
                $this->processEvent($event);
            }

            // In safe mode, always acknowledge 200 even if downstream reply fails
            return response()->json(['ok' => true, 'mode' => ($this->alwaysAck ? 'always_ack' : 'normal')]);

        } catch (\Throwable $e) {
            Log::error('[LINE Webhook] Unhandled error', [
                'error' => $e->getMessage(),
                'file'  => $e->getFile(),
                'line'  => $e->getLine(),
                'trace' => $e->getTraceAsString(),
            ]);

            // Safe mode: never surface 5xx/4xx to LINE (prevents retry/"เด้งออก")
            if ($this->alwaysAck || env('APP_DEBUG', false)) {
                return response()->json([
                    'ok'    => false,
                    'error' => $e->getMessage(),
                    'mode'  => $this->alwaysAck ? 'always_ack' : 'debug',
                ], 200);
            }

            return response()->json(['error' => 'Internal server error'], 500);
        }
    }

    /**
     * Process a single event
     */
    /**
     * @param array<string, mixed> $event
     */
    private function processEvent(array $event): void
    {
        try {
            $eventType  = $event['type']             ?? '';
            $userId     = $event['source']['userId'] ?? 'unknown';
            $replyToken = $event['replyToken']       ?? null;

            Log::info('[LINE Webhook] Processing event', [
                'type'   => $eventType,
                'userId' => $userId,
            ]);

            // Check allowlist (only enforce when list is non-empty)
            if (count($this->allowlist) > 0 && !in_array($userId, $this->allowlist, true)) {
                Log::warning('[LINE Webhook] User not in allowlist', ['userId' => $userId]);
                return;
            }

            // Fast-path intents handled here (before delegating to NextPlotService)
            if ($eventType === 'message' && isset($event['message']) && ($event['message']['type'] ?? '') === 'text') {
                $text        = (string) ($event['message']['text'] ?? '');
                $sanitized   = $this->sanitizeText($text);
                $t           = mb_strtolower($sanitized, 'UTF-8');
                $commandKey  = $this->normalizeCommandKey($text);
                // whoami / id
                $whoCmds = ['id','id?','whoami','whoami?','userid','ไอดี','ไอดี?'];
                if (in_array($commandKey, $whoCmds, true)) {
                    $lines = [
                        'นี่คือ LINE userId ของคุณ:',
                        $userId,
                        '',
                        'นำค่านี้ไปตั้งค่าใน .env เช่น',
                        'NEXTPLOT_OWNER_LINE_USER_IDS="'.$userId.'"',
                    ];
                    if ($replyToken) { $this->sendReply($replyToken, ['type'=>'text','text'=>implode("\n", $lines)]); }
                    return;
                }

                // Area search: "มีที่ <พื้นที่> ไหม"
                $tNoFormat = preg_replace('/[\p{Cf}]+/u', '', $t) ?? $t;
                if (preg_match('/^มีที่\s*(.+?)\s*(?:ไหม|มั้ย)\??$/u', $tNoFormat, $mm) === 1) {
                    $where = trim($mm[1] ?? '');
                    try {
                        $baseUrl    = (string) config('nextplot.supabase.url', '');
                        $serviceKey = (string) config('nextplot.supabase.service_role', '');
                        $sql = new SupabaseSqlClient($baseUrl, $serviceKey);
                        $esc = function(string $v): string { return str_replace("'", "''", $v); };
                        $w = $esc($where);
                        $cond = "(province ILIKE '%{$w}%' OR district ILIKE '%{$w}%' OR subdistrict ILIKE '%{$w}%' OR description ILIKE '%{$w}%' OR notes ILIKE '%{$w}%')";
                        $count = (int) (($sql->query("SELECT COUNT(*) AS n FROM public.properties WHERE {$cond}")[0]['n'] ?? 0));
                        if ($count > 0) {
                            $rows = $sql->query("SELECT code, deed_number, province, district, subdistrict FROM public.properties WHERE {$cond} ORDER BY COALESCE(finalized_at, created_at) DESC NULLS LAST LIMIT 3");
                            $lines = ["พบที่ดินตรงกับ \"{$where}\" จำนวน {$count} แปลง", 'ตัวอย่าง:'];
                            foreach ($rows as $it) {
                                $code = $it['code'] ?? ($it['id'] ?? '-');
                                $deed = isset($it['deed_number']) && $it['deed_number'] ? (' โฉนด:' . $it['deed_number']) : '';
                                $loc  = implode(' ', array_values(array_filter([$it['province'] ?? null, $it['district'] ?? null, $it['subdistrict'] ?? null])));
                                $lines[] = '• ' . $code . $deed . ($loc ? " ({$loc})" : '');
                            }
                            if ($replyToken) { $this->sendReply($replyToken, ['type'=>'text','text'=>implode("\n", $lines)]); }
                        } else {
                            if ($replyToken) { $this->sendReply($replyToken, ['type'=>'text','text'=>"ยังไม่พบข้อมูลที่ตรงกับ \"{$where}\""]); }
                        }
                    } catch (\Throwable $e) {
                        if ($replyToken) { $this->sendReply($replyToken, ['type'=>'text','text'=>'ยังไม่มีข้อมูลหรือไม่สามารถสอบถามฐานข้อมูลได้ในขณะนี้']); }
                    }
                    return;
                }
            }

            // Removed: generic save for all messages.
            // Now NextPlotService decides selectively what to persist.

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

    private function sanitizeText(string $text): string
    {
        $cleaned = preg_replace('/[\p{Cf}]+/u', '', $text) ?? $text;
        return trim($cleaned);
    }

    private function normalizeCommandKey(string $text): string
    {
        $phrase = mb_strtolower($this->sanitizeText($text), 'UTF-8');
        $compact = preg_replace('/[\p{Z}\s\p{Cc}\p{Cf}]+/u', '', $phrase);
        return $compact ?? '';
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
    /**
     * @param array<string, mixed> $message
     */
    private function sendReply(string $replyToken, array $message): void
    {
        try {
            $url = 'https://api.line.me/v2/bot/message/reply';

            $response = Http::withHeaders([
                'Authorization' => "Bearer {$this->accessToken}",
                'Content-Type'  => 'application/json',
            ])->post($url, [
                'replyToken' => $replyToken,
                'messages'   => [$message],
            ]);

            if ($response->successful()) {
                Log::info('[LINE Webhook] Reply sent', [
                    'replyToken' => $replyToken,
                    'message'    => $message,
                ]);
            } else {
                Log::error('[LINE Webhook] Reply failed', [
                    'replyToken' => $replyToken,
                    'status'     => $response->status(),
                    'body'       => $response->body(),
                ]);
            }

        } catch (\Exception $e) {
            Log::error('[LINE Webhook] Reply error', [
                'replyToken' => $replyToken,
                'error'      => $e->getMessage(),
            ]);
        }
    }
}
