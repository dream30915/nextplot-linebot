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

    // Regex patterns for validation
    private const PATTERN_CODE = '/[A-Z]{2,10}-\d{1,4}/u';
    private const PATTERN_DEED = '/(โฉนด|น\.ส\.3)\s*\d+/u';

    public function __construct(SupabaseService $supabase, ConversationLogger $logger)
    {
        $this->supabase = $supabase;
        $this->lineAccessToken = config('nextplot.line.access_token');
        $this->bucketName = config('nextplot.supabase.bucket_name', 'nextplot');
        $this->logger = $logger;
    }

    /**
     * Process a LINE webhook event
     *
     * @param array $event LINE event object
     * @return array|null Reply message to send back to LINE
     */
    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>|null
     */
    public function processEvent(array $event): ?array
    {
        $eventType = $event['type'] ?? '';
        $userId = $event['source']['userId'] ?? 'unknown';

        Log::info("[NextPlot] Processing event", [
            'type' => $eventType,
            'userId' => $userId,
        ]);

        switch ($eventType) {
            case 'message':
                return $this->handleMessage($event);

            case 'postback':
                return $this->handlePostback($event);

            default:
                Log::info("[NextPlot] Unhandled event type", ['type' => $eventType]);
                return null;
        }
    }

    /**
     * Handle message events (text, image, file)
     */
    /**
     * @param array<string, mixed> $event
     * @return array<string, mixed>|null
     */
    private function handleMessage(array $event): ?array
    {
        $message = $event['message'] ?? [];
        $messageType = $message['type'] ?? '';
        $messageId = $message['id'] ?? '';
        $userId = $event['source']['userId'] ?? 'unknown';

        switch ($messageType) {
            case 'text':
                return $this->handleTextMessage($event);

            case 'image':
            case 'video':
            case 'audio':
            case 'file':
                return $this->handleMediaMessage($event);

            default:
                Log::info("[NextPlot] Unhandled message type", ['type' => $messageType]);
                return null;
        }
    }

    /**
     * Handle text messages
     *
     * @param array<string, mixed> $event
     * @return array<string, mixed>
     */
    private function handleTextMessage(array $event): array
    {
        $text = $event['message']['text'] ?? '';
        $userId = $event['source']['userId'] ?? 'unknown';

        Log::info('[NextPlot] Text message', [
            'userId' => $userId,
            'text' => $text,
        ]);

        // Help / Usage
        if ($this->isHelpCommand($text)) {
            return [
                'type' => 'text',
                'text' => "วิธีใช้\n- พิมพ์ CODE และเลขโฉนดในข้อความเดียวกัน เช่น: WC-007 โฉนด 8899\n- ส่งรูป/ไฟล์แนบได้ ระบบจะอัปโหลดและส่งลิงก์กลับ\n- คำสั่ง: help, วิธีใช้",
            ];
        }

        // Extract CODE and เลขโฉนด from text
        $hasCode = preg_match(self::PATTERN_CODE, $text, $codeMatches);
        $hasDeed = preg_match(self::PATTERN_DEED, $text, $deedMatches);

        $code = $hasCode ? $codeMatches[0] : null;
        $deed = $hasDeed ? $deedMatches[0] : null;

        // Check if data is complete
        if (!$code || !$deed) {
            return $this->generateQuickReply($code, $deed);
        }

        // Data is complete, save to database (and file)
        $record = [
            'user_id' => $userId,
            'event_type' => 'text',
            'text_content' => $text,
            'raw' => $event,
        ];
        $this->supabase->insertRow('messages', $record);
        $this->logger->append($record);

        return [
            'type' => 'text',
            'text' => "✅ บันทึกข้อมูลเรียบร้อย\n\nCODE: {$code}\nเลขโฉนด: {$deed}\nไฟล์: storage/app/conversations.ndjson",
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
        $messageId = $event['message']['id'] ?? '';
        $messageType = $event['message']['type'] ?? '';
        $userId = $event['source']['userId'] ?? 'unknown';

        Log::info("[NextPlot] Media message", [
            'userId' => $userId,
            'type' => $messageType,
            'messageId' => $messageId,
        ]);

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
        $now = now();
        $extension = $this->getExtensionForType($messageType);
        $filename = "{$messageId}.{$extension}";
        $path = "line/{$now->format('Y')}/{$now->format('m')}/{$now->format('d')}/{$filename}";

        // Upload to Supabase Storage
        $contentType = $this->getContentTypeForType($messageType);
        $uploaded = $this->supabase->uploadBuffer($this->bucketName, $path, $content, $contentType);

        if (!$uploaded) {
            Log::error('[NextPlot] Failed to upload to Storage', ['path' => $path]);
            return [
                'type' => 'text',
                'text' => '❌ ไม่สามารถอัปโหลดไฟล์ได้',
            ];
        }

        // Generate signed URL
        $signedUrl = $this->supabase->signPath($this->bucketName, $path, 3600);

        // Save to database (and file)
        $record = [
            'user_id' => $userId,
            'event_type' => $messageType,
            'text_content' => $signedUrl ?? $path,
            'raw' => $event,
        ];
        $this->supabase->insertRow('messages', $record);
        $this->logger->append($record);

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
        $data = $event['postback']['data'] ?? '';
        $userId = $event['source']['userId'] ?? 'unknown';

        Log::info("[NextPlot] Postback", [
            'userId' => $userId,
            'data' => $data,
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
        if (!$code) $missing[] = 'CODE';
        if (!$deed) $missing[] = 'เลขโฉนด';

        $text = "⚠️ ข้อมูลยังไม่ครบ: " . implode(', ', $missing);

        return [
            'type' => 'text',
            'text' => $text,
            'quickReply' => [
                'items' => [
                    [
                        'type' => 'action',
                        'action' => [
                            'type' => 'postback',
                            'label' => '➕ เพิ่ม CODE',
                            'data' => 'action=add_code',
                            'displayText' => 'เพิ่ม CODE',
                        ],
                    ],
                    [
                        'type' => 'action',
                        'action' => [
                            'type' => 'postback',
                            'label' => '➕ เพิ่มเลขโฉนด',
                            'data' => 'action=add_deed',
                            'displayText' => 'เพิ่มเลขโฉนด',
                        ],
                    ],
                    [
                        'type' => 'action',
                        'action' => [
                            'type' => 'postback',
                            'label' => '⏩ ข้าม',
                            'data' => 'action=skip',
                            'displayText' => 'ข้าม',
                        ],
                    ],
                ],
            ],
        ];
    }

    private function isHelpCommand(string $text): bool
    {
        $t = mb_strtolower(trim($text), 'UTF-8');
        return in_array($t, ['help', '/help', 'วิธีใช้', 'ใช้งานยังไง'], true);
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

            Log::error("[NextPlot] LINE content fetch failed", [
                'messageId' => $messageId,
                'status' => $response->status(),
            ]);
            return null;

        } catch (\Exception $e) {
            Log::error("[NextPlot] LINE content fetch error", [
                'messageId' => $messageId,
                'error' => $e->getMessage(),
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
            'file' => 'bin',
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
            'file' => 'application/octet-stream',
            default => 'application/octet-stream',
        };
    }
}
