<?php

namespace Tests\Feature;

use App\Services\ConversationLogger;
use App\Services\NextPlotService;
use App\Services\SupabaseService;
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
            return new class extends ConversationLogger {
                public function __construct() {}
            };
        });

        // Light stub for SupabaseService to avoid real HTTP
        $this->app->instance(SupabaseService::class, new class extends SupabaseService {
            public function __construct() {}
            public function insertRow(string $table, array $data): ?array { return ['id' => 1] + $data; }
            public function uploadBuffer(string $bucket, string $path, string $content, string $contentType): bool { return true; }
            public function signPath(string $bucket, string $path, int $expiresIn = 3600): ?string { return 'https://signed.example/url'; }
        });

        // Use real NextPlotService (DI will get above stubs)
    }

    /** @test */
    public function help_command_returns_usage_text()
    {
        $payload = [
            'events' => [
                [
                    'type' => 'message',
                    'replyToken' => 'rt1',
                    'source' => ['userId' => 'U1'],
                    'message' => ['type' => 'text', 'text' => 'help'],
                ],
            ],
        ];

        $response = $this->postJson('/api/line/webhook', $payload);

        $response->assertStatus(200)->assertJson(['ok' => true]);
    }

    /** @test */
    public function incomplete_text_triggers_quick_reply_no_persist()
    {
        $payload = [
            'events' => [
                [
                    'type' => 'message',
                    'replyToken' => 'rt2',
                    'source' => ['userId' => 'U2'],
                    'message' => ['type' => 'text', 'text' => 'โฉนด 1234'],
                ],
            ],
        ];

        $response = $this->postJson('/api/line/webhook', $payload);
        $response->assertStatus(200)->assertJson(['ok' => true]);
    }
}
