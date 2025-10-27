<?php

namespace Tests\Feature;

use App\Services\NextPlotService;
use Tests\Support\CountingNextPlotService;
use Tests\TestCase;

class LineWebhookAllowlistTest extends TestCase
{
    private CountingNextPlotService $counterService;

    protected function setUp(): void
    {
        parent::setUp();

        // Configure secrets and signature enforcement
        config()->set('nextplot.line.channel_secret', 'test_secret');
        config()->set('nextplot.line.signature_relaxed', false);

        // Bind a counting fake for NextPlotService
        $this->counterService = new CountingNextPlotService();
        $this->app->instance(NextPlotService::class, $this->counterService);

        // Use real SupabaseService (won't be called by our NextPlotService fake)
    }

    /** @test */
    public function allowed_user_is_processed()
    {
        config()->set('nextplot.line.user_id_allowlist', 'Uallowed');

        $payload = [
            'events' => [[
                'type'    => 'message',
                'source'  => ['userId' => 'Uallowed'],
                'message' => ['type' => 'text', 'text' => 'hello'],
            ]],
        ];

        $body      = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $signature = base64_encode(hash_hmac('sha256', $body, 'test_secret', true));

        $server = [
            'CONTENT_TYPE'          => 'application/json',
            'HTTP_X_LINE_SIGNATURE' => $signature,
            'HTTP_ACCEPT'           => 'application/json',
        ];

        $response = $this->call('POST', '/api/line/webhook', [], [], [], $server, $body);

        $response->assertStatus(200)->assertJson(['ok' => true]);
        $this->assertSame(1, $this->counterService->called, 'NextPlotService should be called for allowed user');
    }

    /** @test */
    public function disallowed_user_is_ignored()
    {
        config()->set('nextplot.line.user_id_allowlist', 'Uallowed');

        $payload = [
            'events' => [[
                'type'    => 'message',
                'source'  => ['userId' => 'Ublocked'],
                'message' => ['type' => 'text', 'text' => 'hello'],
            ]],
        ];

        $body      = json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        $signature = base64_encode(hash_hmac('sha256', $body, 'test_secret', true));

        $server = [
            'CONTENT_TYPE'          => 'application/json',
            'HTTP_X_LINE_SIGNATURE' => $signature,
            'HTTP_ACCEPT'           => 'application/json',
        ];

        $response = $this->call('POST', '/api/line/webhook', [], [], [], $server, $body);

        $response->assertStatus(200)->assertJson(['ok' => true]);
        $this->assertSame(0, $this->counterService->called, 'NextPlotService should NOT be called for disallowed user');
    }
}
