<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * NextPlot Service
 * Translated from: line-webhook-proxy/lib/nextplot.js
 *
 * Business logic for NextPlot system:
 * - Process LINE webhook events (text, image, file)
 * - Validate data completeness (CODE, เลขโฉนด)
 * - Generate Quick Reply messages
 * - Handle media upload to Supabase Storage
 */
class NextPlotService
{
    private SupabaseService $supabase;
    private string $lineAccessToken;
    private string $bucketName;
    private ConversationLogger $logger;
    private UserContextStore $contextStore;
    private ChatService $chat;

    // Regex patterns for validation
    private const PATTERN_CODE = '/[A-Z]{2,10}-\d{1,4}/u';
    private const PATTERN_DEED = '/(โฉนด|น\.ส\.3)\s*\d+/u';

    public function __construct(SupabaseService $supabase, ConversationLogger $logger, UserContextStore $contextStore, ?ChatService $chat = null)
    {
        $this->supabase        = $supabase;
        $this->lineAccessToken = config('nextplot.line.access_token');
        $this->bucketName      = config('nextplot.supabase.bucket_name', 'nextplot');
        $this->logger          = $logger;
        $this->contextStore    = $contextStore;
        $this->chat            = $chat ?? new NullChatService();
    }

    private function tone(): string
    {
        return (string) config('nextplot.bot.tone', 'formal');
    }

    private function sanitizeText(string $text): string
    {
        $cleaned = preg_replace('/[\p{Cf}]+/u', '', $text) ?? $text;
        return trim($cleaned);
    }

    private function normalizedPhrase(string $text): string
    {
        return mb_strtolower($this->sanitizeText($text), 'UTF-8');
    }

    private function normalizeCommandKey(string $text): string
    {
        $phrase = $this->normalizedPhrase($text);
        $compact = preg_replace('/[\p{Z}\s\p{Cc}\p{Cf}]+/u', '', $phrase);
        return $compact ?? '';
    }

    /**
     * Process a LINE webhook event
     *
     * @param array<string, mixed> $event
     * @return array<string, mixed>|null
     */
    public function processEvent(array $event): ?array
    {
        $type = (string) ($event['type'] ?? '');
        if ($type === 'message') {
            return $this->handleMessage($event);
        }
        if ($type === 'postback') {
            return $this->handlePostback($event);
        }
        return null;
    }

    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>|null
     */
    private function handleMessage(array $event): ?array
    {
        $msgType = (string) ($event['message']['type'] ?? '');
        if ($msgType === 'text') {
            return $this->handleTextMessage($event);
        }
        if (in_array($msgType, ['image', 'video', 'audio', 'file'], true)) {
            return $this->handleMediaMessage($event);
        }
        return null;
    }

    /**
     * Handle text messages
     *
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function handleTextMessage(array $event): array
    {
        $textRaw    = (string) ($event['message']['text']  ?? '');
        $text       = $this->sanitizeText($textRaw);
        $userId     = $event['source']['userId'] ?? 'unknown';
        $contextKey = $this->contextKeyFromEvent($event);

        Log::info('[NextPlot] Text message', [
            'userId' => $userId,
            'text'   => $text,
        ]);

        // Update rolling session before any branching
        // Rules:
        // - New session when: user types many dots ("........") OR inactivity > 10s
        // - Session id is 1-based, persisted in context store
        $this->updateSession($contextKey, $text);

        // Quick util: whoami (return LINE userId)
        $commandKey = $this->normalizeCommandKey($textRaw);
        $whoCmds = ['id', 'id?', 'whoami', 'whoami?', 'ไอดี', 'ไอดี?', 'userid'];
        if (in_array($commandKey, $whoCmds, true)) {
            $lines = [
                'นี่คือ LINE userId ของคุณ:',
                $userId,
                '',
                'นำค่านี้ไปตั้งค่าใน .env เช่น',
                'NEXTPLOT_OWNER_LINE_USER_IDS="'.$userId.'"',
            ];
            return [ 'type' => 'text', 'text' => implode("\n", $lines) ];
        }

        // Help / Usage
        if ($this->isHelpCommand($text)) {
            $formal = "วิธีใช้\n"
                . "1) ระบุรหัส CODE และเลขที่โฉนดภายในข้อความเดียว เช่น: WC-007 โฉนด 8899\n"
                . "2) สามารถส่งรูปภาพหรือไฟล์แนบ ระบบจะอัปโหลดและส่งลิงก์สำหรับดาวน์โหลดกลับ\n"
                . "3) คำสั่งที่รองรับ: วิธีใช้, เริ่มใหม่, ต่อจากเดิม";
            $friendly = "วิธีใช้\n- พิมพ์ CODE และเลขโฉนดในข้อความเดียวกัน เช่น: WC-007 โฉนด 8899\n- ส่งรูป/ไฟล์แนบได้ ระบบจะอัปโหลดและส่งลิงก์กลับ\n- คำสั่ง: help, วิธีใช้";
            return [
                'type' => 'text',
                'text' => $this->tone() === 'formal' ? $formal : $friendly,
            ];
        }

        // Reset memory
        if ($this->isResetCommand($text)) {
            $this->contextStore->clear($contextKey);
            return [
                'type' => 'text',
                'text' => $this->tone() === 'formal' ? 'ระบบได้ล้างข้อมูลบริบทของการสนทนานี้เรียบร้อยแล้ว' : '🧹 ล้างความจำสำหรับแชทนี้เรียบร้อย',
            ];
        }

        // Continue from memory
        if ($this->isContinueCommand($text)) {
            $state = $this->contextStore->load($contextKey);
            if (is_array($state) && (!empty($state['code']) || !empty($state['deed']) || !empty($state['last_media_url']))) {
                $lines = ["ใช้ข้อมูลเดิม:"];
                if (!empty($state['code'])) { $lines[] = "- CODE: {$state['code']}"; }
                if (!empty($state['deed'])) { $lines[] = "- เลขโฉนด: {$state['deed']}"; }
                if (!empty($state['last_media_url'])) { $lines[] = "- ไฟล์ล่าสุด: {$state['last_media_url']}"; }
                return [
                    'type' => 'text',
                    'text' => implode("\n", $lines),
                ];
            }
            return [
                'type' => 'text',
                'text' => $this->tone() === 'formal' ? 'ยังไม่มีข้อมูลก่อนหน้า กรุณาระบุรหัส CODE และเลขที่โฉนดเพื่อเริ่มต้น' : 'ยังไม่มีข้อมูลเดิมให้ใช้ ลองส่ง CODE และเลขโฉนดก่อนนะ',
            ];
        }

        // Extract CODE and เลขโฉนด from text
    $hasCode = preg_match(self::PATTERN_CODE, $text, $codeMatches);
    $hasDeed = preg_match(self::PATTERN_DEED, $text, $deedMatches);

        $code = $hasCode ? $codeMatches[0] : null;
        $deed = $hasDeed ? $deedMatches[0] : null;

        // When no structured data is provided, prefer AI chat first; then fallback to small-talk
        if (!$code && !$deed) {
            // Try AI chat if enabled (ChatService may be NullChatService when disabled)
            $state = $this->contextStore->load($contextKey) ?? [];
            $t0 = microtime(true);
            $ai    = $this->chat->generate($text, [
                'state'  => $state,
                'userId' => $userId,
            ]);
            $dtMs = (int) round((microtime(true) - $t0) * 1000);
            if (is_string($ai) && $ai !== '') {
                Log::info('[NextPlot] AI chat used');
                // Telemetry: ai_used
                $this->supabase->recordEvent('ai_used', [
                    'line_user_id'   => $userId,
                    'use_case'       => 'no_structured_data',
                    'latency_ms'     => $dtMs,
                    'model'          => config('nextplot.chat.openai.model'),
                    'prompt_length'  => mb_strlen($text, 'UTF-8'),
                    'response_length'=> mb_strlen($ai, 'UTF-8'),
                    'tone'           => $this->tone(),
                ]);
                return [
                    'type' => 'text',
                    'text' => $ai,
                ];
            }

            // Telemetry: ai_failed (attempted but no response)
            $this->supabase->recordEvent('ai_failed', [
                'line_user_id'  => $userId,
                'use_case'      => 'no_structured_data',
                'latency_ms'    => $dtMs,
                'model'         => config('nextplot.chat.openai.model'),
                'reason'        => 'null_or_empty',
                'prompt_length' => mb_strlen($text, 'UTF-8'),
                'tone'          => $this->tone(),
            ]);

            // Fallback: lightweight small-talk
            $intent = $this->detectSmallTalkIntent($text);
            if ($intent !== null) {
                return $this->replyForSmallTalk($intent);
            }
        }

        // Save partial state if available
        $prev    = $this->contextStore->load($contextKey) ?? [];
        $partial = $prev;
        if ($code) { $partial['code'] = $code; }
        if ($deed) { $partial['deed'] = $deed; }
        if (!empty($partial)) {
            $partial['updated_at'] = now()->toIso8601String();
            $this->contextStore->save($contextKey, $partial);
        }

        // If neither CODE nor deed detected, don't nag; reply friendly small-talk style (fallback)
        if (!$code && !$deed) {
            return $this->replyForSmallTalk('default');
        }

        // If only one of them is present, try AI to ask for the missing field; fallback to Quick Reply
        if (($code && !$deed) || (!$code && $deed)) {
            // Prefer AI if available
            $state = $this->contextStore->load($contextKey) ?? [];
            $missing = !$code ? 'CODE' : 'เลขโฉนด';
            $prompt = "ผู้ใช้พิมพ์: {$text}\nข้อมูลที่มี: CODE=" . ($code ?: '-') . ", โฉนด=" . ($deed ?: '-') . "\nโปรดตอบแบบสุภาพ กระชับ และถามต่อเพื่อขอ {$missing} ให้ครบเพื่อดำเนินการต่อ";
            $t0 = microtime(true);
            $ai = $this->chat->generate($prompt, [
                'state'  => $state,
                'userId' => $userId,
                'known'  => ['code' => $code, 'deed' => $deed],
                'missing'=> $missing,
            ]);
            $dtMs = (int) round((microtime(true) - $t0) * 1000);
            if (is_string($ai) && $ai !== '') {
                Log::info('[NextPlot] AI chat used (partial data)');
                // Telemetry: ai_used
                $this->supabase->recordEvent('ai_used', [
                    'line_user_id'    => $userId,
                    'use_case'        => 'partial_structured_data',
                    'latency_ms'      => $dtMs,
                    'model'           => config('nextplot.chat.openai.model'),
                    'prompt_length'   => mb_strlen($prompt, 'UTF-8'),
                    'response_length' => mb_strlen($ai, 'UTF-8'),
                    'known'           => ['code' => $code, 'deed' => $deed],
                    'missing'         => $missing,
                    'tone'            => $this->tone(),
                ]);
                return [
                    'type' => 'text',
                    'text' => $ai,
                ];
            }
            // Telemetry: ai_failed (attempted but no response)
            $this->supabase->recordEvent('ai_failed', [
                'line_user_id'  => $userId,
                'use_case'      => 'partial_structured_data',
                'latency_ms'    => $dtMs,
                'model'         => config('nextplot.chat.openai.model'),
                'reason'        => 'null_or_empty',
                'prompt_length' => mb_strlen($prompt, 'UTF-8'),
                'known'         => ['code' => $code, 'deed' => $deed],
                'missing'       => $missing,
                'tone'          => $this->tone(),
            ]);
            // Fallback to Quick Reply
            return $this->generateQuickReply($code, $deed);
        }

        // Data is complete, record event (and append to local log)
        $eventData = [
            'line_user_id' => $userId,
            'text'         => $text,
            'raw'          => $event,
        ];
        $saved = $this->supabase->recordEvent('message_received', $eventData);
        $this->logger->append([
            'event_type' => 'message_received',
            'data'       => $eventData,
            'saved'      => (bool) $saved,
        ]);

        // Save complete snapshot
        $snapshot = [
            'code'       => $code,
            'deed'       => $deed,
            'updated_at' => now()->toIso8601String(),
        ];
        $this->contextStore->save($contextKey, $snapshot);

        $formalConfirm = "ระบบได้บันทึกข้อมูลเรียบร้อยแล้ว\n\nCODE: {$code}\nเลขที่โฉนด: {$deed}\nไฟล์บันทึก: storage/app/conversations.ndjson";
        $friendlyConfirm = "✅ บันทึกข้อมูลเรียบร้อย\n\nCODE: {$code}\nเลขโฉนด: {$deed}\nไฟล์: storage/app/conversations.ndjson";
        return [
            'type' => 'text',
            'text' => $this->tone() === 'formal' ? $formalConfirm : $friendlyConfirm,
        ];
    }

    /**
     * Handle media messages (image, file, etc.)
     *
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function handleMediaMessage(array $event): array
    {
    $messageId   = $event['message']['id']    ?? '';
    $messageType = $event['message']['type']  ?? '';
    $userId      = $event['source']['userId'] ?? 'unknown';
    $contextKey  = $this->contextKeyFromEvent($event);

        Log::info('[NextPlot] Media message', [
            'userId'    => $userId,
            'type'      => $messageType,
            'messageId' => $messageId,
        ]);

        // Update/maintain session on media (inactivity-based)
        $sessionId = $this->updateSession($contextKey, null);

        // Download content from LINE
        $content = $this->fetchLineContent($messageId);
        if (!$content) {
            Log::error('[NextPlot] Failed to download LINE content', ['messageId' => $messageId]);
            return [
                'type' => 'text',
                'text' => '❌ ไม่สามารถดาวน์โหลดไฟล์ได้',
            ];
        }

        // Generate storage path
        $now       = now();
        $extension = $this->getExtensionForType($messageType);
        // Auto-naming: {CODE}-{RUN}_{messageId}.{ext}
        $state  = $this->contextStore->load($contextKey) ?? [];
        $code   = is_string($state['code'] ?? null) ? $state['code'] : null;
        $runStr = $sessionId > 0 ? sprintf('%02d', (int)$sessionId) : null;
        $prefix = '';
        if ($code && $runStr) {
            $prefix = $code . '-' . $runStr . '_';
        } elseif ($runStr) {
            $prefix = 'S' . $runStr . '_';
        }
        $filename  = $prefix . $messageId . ".{$extension}";
        $path      = "line/{$now->format('Y')}/{$now->format('m')}/{$now->format('d')}/{$filename}";

        // Upload to Supabase Storage
        $contentType = $this->getContentTypeForType($messageType);
        $uploaded    = $this->supabase->uploadBuffer($this->bucketName, $path, $content, $contentType);

        if (!$uploaded) {
            Log::error('[NextPlot] Failed to upload to Storage', ['path' => $path]);
            return [
                'type' => 'text',
                'text' => '❌ ไม่สามารถอัปโหลดไฟล์ได้',
            ];
        }

        // Generate signed URL
        $signedUrl = $this->supabase->signPath($this->bucketName, $path, 3600);

        // Record event (and append to local log)
        $eventData = [
            'line_user_id' => $userId,
            'media_type'   => $messageType,
            'path'         => $path,
            'signed_url'   => $signedUrl,
            'raw'          => $event,
        ];
        $saved = $this->supabase->recordEvent('media_uploaded', $eventData);
        $this->logger->append([
            'event_type' => 'media_uploaded',
            'data'       => $eventData,
            'saved'      => (bool) $saved,
        ]);

    // Save last media URL in snapshot
    $prev                   = $this->contextStore->load($contextKey) ?? [];
    $prev['last_media_url'] = $signedUrl ?? $path;
    $prev['updated_at']     = now()->toIso8601String();
    $this->contextStore->save($contextKey, $prev);

        return [
            'type' => 'text',
            'text' => "✅ อัปโหลดไฟล์เรียบร้อย\n\nประเภท: {$messageType}\nลิงก์ (ใช้ได้ 1 ชม.): {$signedUrl}\nไฟล์: storage/app/conversations.ndjson",
        ];
    }

    /**
     * Handle postback events (from Quick Reply buttons)
     */
    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>|null
     */
    private function handlePostback(array $event): ?array
    {
        $data   = $event['postback']['data'] ?? '';
        $userId = $event['source']['userId'] ?? 'unknown';

        Log::info('[NextPlot] Postback', [
            'userId' => $userId,
            'data'   => $data,
        ]);

        // Parse postback data
        parse_str($data, $params);
        $action = $params['action'] ?? '';

        switch ($action) {
            case 'add_code':
                return [
                    'type' => 'text',
                    'text' => 'โปรดพิมพ์ CODE ในรูปแบบ: XX-999 (เช่น WC-007)',
                ];

            case 'add_deed':
                return [
                    'type' => 'text',
                    'text' => 'โปรดพิมพ์เลขโฉนด (เช่น โฉนด 8899)',
                ];

            case 'skip':
                return [
                    'type' => 'text',
                    'text' => '⏩ ข้ามการบันทึกข้อมูล',
                ];

            default:
                return null;
        }
    }

    /**
     * Generate Quick Reply message when data is incomplete
     *
     * @return array<string, mixed>
     */
    private function generateQuickReply(?string $code, ?string $deed): array
    {
        $missing = [];
        if (!$code) {
            $missing[] = 'CODE';
        }
        if (!$deed) {
            $missing[] = 'เลขโฉนด';
        }

        $text = $this->tone() === 'formal'
            ? ('ข้อมูลยังไม่สมบูรณ์ กรุณาเพิ่ม: ' . implode(', ', $missing))
            : ('⚠️ ข้อมูลยังไม่ครบ: ' . implode(', ', $missing));

        return [
            'type'       => 'text',
            'text'       => $text,
            'quickReply' => [
                'items' => [
                    [
                        'type'   => 'action',
                        'action' => [
                            'type'        => 'postback',
                            'label'       => ($this->tone() === 'formal' ? 'เพิ่มรหัส CODE' : '➕ เพิ่ม CODE'),
                            'data'        => 'action=add_code',
                            'displayText' => ($this->tone() === 'formal' ? 'เพิ่มรหัส CODE' : 'เพิ่ม CODE'),
                        ],
                    ],
                    [
                        'type'   => 'action',
                        'action' => [
                            'type'        => 'postback',
                            'label'       => ($this->tone() === 'formal' ? 'เพิ่มเลขที่โฉนด' : '➕ เพิ่มเลขโฉนด'),
                            'data'        => 'action=add_deed',
                            'displayText' => ($this->tone() === 'formal' ? 'เพิ่มเลขที่โฉนด' : 'เพิ่มเลขโฉนด'),
                        ],
                    ],
                    [
                        'type'   => 'action',
                        'action' => [
                            'type'        => 'postback',
                            'label'       => ($this->tone() === 'formal' ? 'ข้ามขั้นตอน' : '⏩ ข้าม'),
                            'data'        => 'action=skip',
                            'displayText' => ($this->tone() === 'formal' ? 'ข้ามขั้นตอน' : 'ข้าม'),
                        ],
                    ],
                ],
            ],
        ];
    }

    private function isHelpCommand(string $text): bool
    {
        $t = $this->normalizedPhrase($text);
        return in_array($t, ['help', '/help', 'วิธีใช้', 'ใช้งานยังไง', 'menu', 'เมนู'], true);
    }

    private function isContinueCommand(string $text): bool
    {
        $t = $this->normalizedPhrase($text);
        return in_array($t, ['ต่อจากเดิม', 'ใช้ข้อมูลเดิม', 'continue', 'resume'], true);
    }

    private function isResetCommand(string $text): bool
    {
        $t = $this->normalizedPhrase($text);
        if (in_array($t, ['เริ่มใหม่', 'reset', '/reset'], true)) {
            return true;
        }
        // Treat a streak of many dots as a soft reset marker (e.g., "........")
        if (preg_match('/\.{6,}/u', $text) === 1) {
            return true;
        }
        return false;
    }

        /**
         * Update and return current session id for a context.
         * Rules:
         * - Increment session when reset marker is present in incoming text.
         * - Increment session when inactivity > 10 seconds since last activity.
         * - Persist session_id (int) and last_activity_at (ISO8601) in context store.
         */
        private function updateSession(string $contextKey, ?string $incomingText): int
        {
            $state = $this->contextStore->load($contextKey) ?? [];
            $now   = now();
            $sid   = (int) ($state['session_id'] ?? 0);
            if ($sid <= 0) { $sid = 1; }

            $lastAtStr = isset($state['last_activity_at']) && is_string($state['last_activity_at'])
                ? $state['last_activity_at']
                : null;

            $shouldIncrement = false;

            // Reset by dots (e.g., "........")
            if (is_string($incomingText) && preg_match('/\.{6,}/u', $incomingText) === 1) {
                $shouldIncrement = true;
            }

            // Inactivity > 10 seconds
            if (!$shouldIncrement && $lastAtStr) {
                try {
                    $last = \Carbon\Carbon::parse($lastAtStr);
                    if ($now->diffInSeconds($last) > 10) {
                        $shouldIncrement = true;
                    }
                } catch (\Throwable $e) {
                    // ignore parse errors and keep current session
                }
            }

            if ($shouldIncrement) {
                $sid += 1;
            }

            // Persist
            $state['session_id']       = $sid;
            $state['last_activity_at'] = $now->toIso8601String();
            $this->contextStore->save($contextKey, $state);

            return $sid;
        }
    /**
     * Very small rule-based intent detection for greetings/thanks/help
     */
    private function detectSmallTalkIntent(string $text): ?string
    {
        $t = mb_strtolower(trim($text), 'UTF-8');
        if ($t === '') { return null; }

        $greetings = ['สวัสดี', 'หวัดดี', 'ดีครับ', 'ดีค่ะ', 'hello', 'hi', 'hey'];
        foreach ($greetings as $g) {
            if (mb_strpos($t, mb_strtolower($g, 'UTF-8')) !== false) {
                return 'greeting';
            }
        }

        $thanks = ['ขอบคุณ', 'ขอบใจ', 'thanks', 'thank you', 'thx'];
        foreach ($thanks as $k) {
            if (mb_strpos($t, mb_strtolower($k, 'UTF-8')) !== false) {
                return 'thanks';
            }
        }

        $who = ['คุณคือใคร', 'เธอคือใคร', 'who are you'];
        foreach ($who as $w) {
            if (mb_strpos($t, mb_strtolower($w, 'UTF-8')) !== false) {
                return 'who';
            }
        }

        $help = ['ช่วยด้วย', 'ขอความช่วยเหลือ', 'ช่วยแนะนำ', 'help me'];
        foreach ($help as $h) {
            if (mb_strpos($t, mb_strtolower($h, 'UTF-8')) !== false) {
                return 'help';
            }
        }

        return null;
    }

    /**
     * Small-talk responses
     * @return array<string, mixed>
     */
    private function replyForSmallTalk(string $intent): array
    {
        $formal = $this->tone() === 'formal';
        switch ($intent) {
            case 'greeting':
                return [
                    'type' => 'text',
                    'text' => $formal
                        ? 'สวัสดีครับ/ค่ะ ระบบผู้ช่วย NextPlot พร้อมให้บริการ หากต้องการบันทึกข้อมูล โปรดระบุรหัส CODE และเลขที่โฉนดในข้อความเดียว เช่น WC-007 โฉนด 8899'
                        : 'สวัสดีค่ะ ฉันคือผู้ช่วย NextPlot ช่วยบันทึก CODE และเลขโฉนดได้ ลองพิมพ์เช่น: WC-007 โฉนด 8899',
                ];
            case 'thanks':
                return [
                    'type' => 'text',
                    'text' => $formal
                        ? 'ยินดีให้ความช่วยเหลือ หากต้องการดูวิธีใช้ โปรดพิมพ์: วิธีใช้'
                        : 'ยินดีเสมอค่ะ ถ้าต้องการวิธีใช้พิมพ์: วิธีใช้',
                ];
            case 'who':
                return [
                    'type' => 'text',
                    'text' => $formal
                        ? 'ระบบผู้ช่วย NextPlot ถูกออกแบบเพื่อช่วยจัดเก็บและจัดการข้อมูลแปลงที่ดิน รวมถึงการรับไฟล์แนบผ่าน LINE'
                        : 'ฉันคือบอทผู้ช่วยสำหรับ NextPlot ช่วยจัดการข้อมูลแปลงและไฟล์แนบใน LINE ค่ะ',
                ];
            case 'help':
                return [
                    'type' => 'text',
                    'text' => $formal
                        ? ("วิธีใช้\n"
                            . "1) ระบุรหัส CODE และเลขที่โฉนดภายในข้อความเดียว เช่น: WC-007 โฉนด 8899\n"
                            . "2) สามารถส่งรูปภาพหรือไฟล์แนบ ระบบจะอัปโหลดและส่งลิงก์สำหรับดาวน์โหลดกลับ\n"
                            . "3) คำสั่งที่รองรับ: วิธีใช้, เริ่มใหม่, ต่อจากเดิม")
                        : "วิธีใช้\n- พิมพ์ CODE และเลขโฉนดในข้อความเดียวกัน เช่น: WC-007 โฉนด 8899\n- ส่งรูป/ไฟล์แนบได้ ระบบจะอัปโหลดและส่งลิงก์กลับ\n- คำสั่ง: help, วิธีใช้, เริ่มใหม่",
                ];
            default:
                return [
                    'type' => 'text',
                    'text' => $formal
                        ? 'รับทราบ หากต้องการบันทึกข้อมูล โปรดระบุรหัส CODE และเลขที่โฉนดภายในข้อความเดียว เช่น: WC-007 โฉนด 8899'
                        : 'รับทราบค่ะ หากต้องการบันทึกข้อมูล โปรดพิมพ์ CODE และเลขโฉนดในข้อความเดียวกัน เช่น: WC-007 โฉนด 8899',
                ];
        }
    }

    /**
     * @param array<string, mixed> $event
     */
    private function contextKeyFromEvent(array $event): string
    {
        $source = $event['source'] ?? [];
        $scope  = (string) config('nextplot.context.scope', 'chat');

        // If scope is 'user' and userId is available, prefer per-user key across chats
        if ($scope === 'user' && !empty($source['userId'])) {
            return 'user:' . (string) $source['userId'];
        }

        // Default per-chat key (group > room > user)
        if (!empty($source['groupId'])) {
            return 'group:' . (string) $source['groupId'];
        }
        if (!empty($source['roomId'])) {
            return 'room:' . (string) $source['roomId'];
        }
        $uid = (string) ($source['userId'] ?? 'unknown');
        return 'user:' . $uid;
    }

    /**
     * Fetch content from LINE CDN
     */
    private function fetchLineContent(string $messageId): ?string
    {
        try {
            $url = "https://api-data.line.me/v2/bot/message/{$messageId}/content";

            $response = Http::withHeaders([
                'Authorization' => "Bearer {$this->lineAccessToken}",
            ])->get($url);

            if ($response->successful()) {
                return $response->body();
            }

            Log::error('[NextPlot] LINE content fetch failed', [
                'messageId' => $messageId,
                'status'    => $response->status(),
            ]);
            return null;

        } catch (\Exception $e) {
            Log::error('[NextPlot] LINE content fetch error', [
                'messageId' => $messageId,
                'error'     => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Get file extension for message type
     */
    private function getExtensionForType(string $type): string
    {
        return match($type) {
            'image' => 'jpg',
            'video' => 'mp4',
            'audio' => 'm4a',
            'file'  => 'bin',
            default => 'dat',
        };
    }

    /**
     * Get content type for message type
     */
    private function getContentTypeForType(string $type): string
    {
        return match($type) {
            'image' => 'image/jpeg',
            'video' => 'video/mp4',
            'audio' => 'audio/mp4',
            'file'  => 'application/octet-stream',
            default => 'application/octet-stream',
        };
    }

    /**
     * Minimal small-talk handler (no external AI) toตอบกลับข้อความทั่วไป
     * @return array<string,mixed>|null
     */
    private function smallTalkReply(string $text): ?array
    {
        $t = mb_strtolower(trim($text), 'UTF-8');

        // Greetings
        $greetings = ['สวัสดี', 'หวัดดี', 'hello', 'hi', 'เฮลโล'];
        foreach ($greetings as $g) {
            if (mb_strpos($t, $g, 0, 'UTF-8') !== false) {
                return $this->replyForSmallTalk('greeting');
            }
        }

        // Thanks
        $thanks = ['ขอบคุณ', 'ขอบใจ', 'thanks', 'thank you', 'thx'];
        foreach ($thanks as $w) {
            if (mb_strpos($t, $w, 0, 'UTF-8') !== false) {
                return $this->replyForSmallTalk('thanks');
            }
        }

        // Who/what
        $who = ['คืออะไร', 'คือใคร', 'ทำอะไรได้บ้าง', 'คือใคร?', 'คืออะไร?'];
        foreach ($who as $w) {
            if (mb_strpos($t, $w, 0, 'UTF-8') !== false) {
                return $this->replyForSmallTalk('who');
            }
        }

        // Help-like text without explicit command
        if (mb_strpos($t, 'ช่วย', 0, 'UTF-8') !== false || mb_strpos($t, 'ใช้ยังไง', 0, 'UTF-8') !== false) {
            return $this->replyForSmallTalk('help');
        }

        return null;
    }
}
