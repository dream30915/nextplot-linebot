<?php

namespace Tests\Feature;

use App\Services\NextPlotService;
use App\Services\SupabaseService;
use Illuminate\Support\Str;
use Tests\TestCase;

class LineWebhookSignatureTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();

        // Configure test secrets
        config()->set('nextplot.line.channel_secret', 'test_secret');
        config()->set('nextplot.line.signature_relaxed', false);

        // Bind light-weight test doubles so controller constructor succeeds
        $this->app->instance(NextPlotService::class, new class extends NextPlotService {
            public function __construct() {}
            public function processEvent(array $event): ?array { return null; }
        });

        $this->app->instance(SupabaseService::class, new class extends SupabaseService {
            public function __construct() {}
        });
    }

    /** @test */
    public function webhook_with_valid_signature_returns_200()
    {
        $payload = [
            'events' => [
                [
                    'type' => 'message',
                    'source' => ['userId' => 'UtestUser'],
                    'message' => ['type' => 'text', 'text' => 'hello'],
                ],
            ],
        ];

        $body = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $signature = base64_encode(hash_hmac('sha256', $body, 'test_secret', true));

        $server = [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_LINE_SIGNATURE' => $signature,
            'HTTP_ACCEPT' => 'application/json',
        ];

        $response = $this->call('POST', '/api/line/webhook', [], [], [], $server, $body);

        $response->assertStatus(200)
                 ->assertJson(['ok' => true]);
    }

    /** @test */
    public function webhook_with_invalid_signature_returns_401()
    {
        $payload = [
            'events' => [
                [
                    'type' => 'message',
                    'source' => ['userId' => 'UtestUser'],
                    'message' => ['type' => 'text', 'text' => 'hello'],
                ],
            ],
        ];

        $body = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $badSignature = 'this-is-not-valid';

        $server = [
            'CONTENT_TYPE' => 'application/json',
            'HTTP_X_LINE_SIGNATURE' => $badSignature,
            'HTTP_ACCEPT' => 'application/json',
        ];

        $response = $this->call('POST', '/api/line/webhook', [], [], [], $server, $body);

        $response->assertStatus(401)
                 ->assertJsonFragment(['error' => 'Invalid signature']);
    }
}
