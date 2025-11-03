<?php

namespace Tests\Feature;

use App\Services\ConversationLogger;
use App\Services\NextPlotService;
use App\Services\SupabaseService;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\TestCase;

class LineWebhookHelpAndLoggingTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        // Ensure local storage disk is available
        config()->set('filesystems.default', 'local');
        config()->set('nextplot.line.channel_secret', 'test_secret');
        config()->set('nextplot.line.signature_relaxed', true); // bypass signature for test

        // Replace ConversationLogger with a stub writing to a temp file within storage/app
        $this->app->bind(ConversationLogger::class, function () {
            return new class () extends ConversationLogger {
                public function __construct()
                {
                }
            };
        });

        // Light stub for SupabaseService to avoid real HTTP
        $this->app->instance(SupabaseService::class, new class () extends SupabaseService {
            public function __construct()
            {
            }
            public function insertRow(string $table, array $data): ?array
            {
                return ['id' => 1] + $data;
            }
            public function uploadBuffer(string $bucket, string $path, string $content, string $contentType): bool
            {
                return true;
            }
            public function signPath(string $bucket, string $path, int $expiresIn = 3600): ?string
            {
                return 'https://signed.example/url';
            }
        });

        // Use real NextPlotService (DI will get above stubs)

        Http::fake();
    }

    /** @test */
    public function help_command_returns_usage_text()
    {
        Http::fake([
            'https://api.line.me/*' => Http::response([], 200),
        ]);

        $payload = [
            'events' => [
                [
                    'type'       => 'message',
                    'replyToken' => 'rt1',
                    'source'     => ['userId' => 'U1'],
                    'message'    => ['type' => 'text', 'text' => 'help'],
                ],
            ],
        ];

        $response = $this->postJson('/api/line/webhook', $payload);

        $response->assertStatus(200)->assertJson(['ok' => true]);
    }

    /** @test */
    public function incomplete_text_triggers_quick_reply_no_persist()
    {
        Http::fake([
            'https://api.line.me/*' => Http::response([], 200),
        ]);

        $payload = [
            'events' => [
                [
                    'type'       => 'message',
                    'replyToken' => 'rt2',
                    'source'     => ['userId' => 'U2'],
                    'message'    => ['type' => 'text', 'text' => 'โฉนด 1234'],
                ],
            ],
        ];

        $response = $this->postJson('/api/line/webhook', $payload);
        $response->assertStatus(200)->assertJson(['ok' => true]);
    }

    /** @test */
    public function whoami_command_returns_user_id()
    {
        Http::fake([
            'https://api.line.me/*' => Http::response([], 200),
        ]);

        $payload = [
            'events' => [
                [
                    'type'       => 'message',
                    'replyToken' => 'rt_who',
                    'source'     => ['userId' => 'U123'],
                    'message'    => ['type' => 'text', 'text' => "WhoAmI"],
                ],
            ],
        ];

        $response = $this->postJson('/api/line/webhook', $payload);

        $response->assertStatus(200)->assertJson(['ok' => true]);

        Http::assertSent(function ($request) {
            if (!str_contains($request->url(), 'https://api.line.me')) {
                return false;
            }
            $data = $request->data();
            $messages = $data['messages'] ?? [];
            $text = $messages[0]['text'] ?? '';
            return str_contains($text, 'U123');
        });
    }

    /** @test */
    public function area_search_handles_text_without_explicit_space()
    {
        config()->set('nextplot.supabase.url', 'https://example.supabase.co');
        config()->set('nextplot.supabase.service_role', 'service-key');

        Http::fake([
            'https://api.line.me/*' => Http::response([], 200),
            'https://example.supabase.co/postgres/v1/query' => Http::sequence()
                ->push(['data' => [['n' => 0]]], 200)
                ->push(['data' => []], 200),
        ]);

        $payload = [
            'events' => [
                [
                    'type'       => 'message',
                    'replyToken' => 'rt_area',
                    'source'     => ['userId' => 'U456'],
                    'message'    => ['type' => 'text', 'text' => 'มีที่ปลวกแดงไหม'],
                ],
            ],
        ];

        $response = $this->postJson('/api/line/webhook', $payload);

        $response->assertStatus(200)->assertJson(['ok' => true]);

        Http::assertSent(function ($request) {
            if (!str_contains($request->url(), 'https://api.line.me')) {
                return false;
            }
            $data = $request->data();
            $messages = $data['messages'] ?? [];
            $text = $messages[0]['text'] ?? '';
            return str_contains($text, 'ยังไม่พบข้อมูลที่ตรงกับ "ปลวกแดง"');
        });
    }
}
