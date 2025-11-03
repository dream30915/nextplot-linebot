<?php

namespace Tests\Unit;

use App\Services\SupabaseService;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SupabaseServicePropertiesTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('nextplot.supabase.url', 'https://example.supabase.co');
        config()->set('nextplot.supabase.service_role', 'service');
        config()->set('nextplot.supabase.anon_key', 'anon');
    }

    /** @test */
    public function it_creates_property()
    {
        Http::fake([
            'https://example.supabase.co/rest/v1/properties' => Http::response([
                ['id' => 'p1', 'code' => 'WC-007', 'status' => 'draft']
            ], 201),
        ]);

        $svc = new SupabaseService();
        $row = $svc->createProperty(['code' => 'WC-007']);
        $this->assertIsArray($row);
        $this->assertSame('p1', $row['id'] ?? null);
    }

    /** @test */
    public function it_updates_property()
    {
        Http::fake([
            'https://example.supabase.co/rest/v1/properties*' => Http::response([
                ['id' => 'p1', 'code' => 'WC-007', 'status' => 'pending']
            ], 200),
        ]);

        $svc = new SupabaseService();
        $row = $svc->updateProperty('p1', ['status' => 'pending']);
        $this->assertIsArray($row);
        $this->assertSame('pending', $row['status'] ?? null);
    }

    /** @test */
    public function it_finalizes_property()
    {
        Http::fake([
            'https://example.supabase.co/rest/v1/properties*' => Http::response([
                ['id' => 'p1', 'status' => 'finalized', 'finalized_at' => '2025-10-28T00:00:00Z']
            ], 200),
        ]);

        $svc = new SupabaseService();
        $row = $svc->finalizeProperty('p1');
        $this->assertIsArray($row);
        $this->assertSame('finalized', $row['status'] ?? null);
    }

    /** @test */
    public function it_gets_property_by_id()
    {
        Http::fake([
            'https://example.supabase.co/rest/v1/properties*' => Http::response([
                ['id' => 'p1', 'code' => 'WC-007']
            ], 200),
        ]);

        $svc = new SupabaseService();
        $row = $svc->getPropertyById('p1');
        $this->assertIsArray($row);
        $this->assertSame('p1', $row['id'] ?? null);
    }

    /** @test */
    public function it_lists_property_summaries()
    {
        Http::fake([
            'https://example.supabase.co/rest/v1/properties_summary*' => Http::response([
                ['id' => 'p1', 'code' => 'WC-007', 'status' => 'draft'],
                ['id' => 'p2', 'code' => 'WC-008', 'status' => 'pending'],
            ], 200),
        ]);

        $svc = new SupabaseService();
        $rows = $svc->listPropertySummaries(['status' => 'draft', 'limit' => 1]);
        $this->assertIsArray($rows);
        $this->assertNotEmpty($rows);
        $this->assertSame('WC-007', $rows[0]['code'] ?? null);
    }
}
