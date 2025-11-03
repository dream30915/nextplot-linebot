<?php

namespace Tests\Feature;

use Tests\TestCase;

class AggregatesEndpointTest extends TestCase
{
    /** @test */
    public function aggregates_endpoint_returns_json_shape_even_when_unconfigured(): void
    {
        $response = $this->getJson('/api/nextplot/aggregates');

        $response->assertStatus(200)
            ->assertJsonStructure([
                'ok',
                'total'   => ['sqm', 'rai'],
                'counts'  => ['properties', 'deeds'],
                'top_finder',
                'latest_plot',
            ]);
    }
}
