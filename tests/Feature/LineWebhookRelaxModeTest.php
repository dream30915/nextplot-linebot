<?php

namespace Tests\Feature;

use App\Services\NextPlotService;
use App\Services\SupabaseService;
use Tests\TestCase;

class LineWebhookRelaxModeTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        // Bind minimal fakes so controller constructor succeeds
        $this->app->instance(NextPlotService::class, new class extends NextPlotService {
            public function __construct() {}
            public function processEvent(array $event): ?array { return null; }
        });
    // Use real SupabaseService (not invoked in relax mode)
    }

    /** @test */
    public function relax_mode_bypasses_signature_and_returns_ok()
    {
        // Enable RELAX mode for this test
        putenv('LINE_WEBHOOK_RELAX_VERIFY=true');

        $payload = [ 'events' => [] ];
        $body = json_encode($payload);
        $server = [ 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT' => 'application/json'];

        $response = $this->call('POST', '/api/line/webhook', [], [], [], $server, $body);

        $response->assertStatus(200)
                 ->assertJson(['ok' => true, 'mode' => 'relax']);

        // Cleanup env
        putenv('LINE_WEBHOOK_RELAX_VERIFY');
    }
}
