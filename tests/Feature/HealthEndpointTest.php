<?php

namespace Tests\Feature;

use Tests\TestCase;

class HealthEndpointTest extends TestCase
{
    /** @test */
    public function health_endpoint_returns_ok_json()
    {
        $response = $this->get('/api/health');

        $response->assertStatus(200)
                 ->assertJsonStructure([
                     'status', 'service', 'timestamp', 'version', 'env' => ['supabase', 'line']
                 ]);
    }
}
