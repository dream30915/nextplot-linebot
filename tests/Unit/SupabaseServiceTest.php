<?php

namespace Tests\Unit;

use App\Services\SupabaseService;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class SupabaseServiceTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('nextplot.supabase.url', 'https://example.supabase.co');
        config()->set('nextplot.supabase.service_role', 'service');
        config()->set('nextplot.supabase.anon_key', 'anon');
    }

    /** @test */
    public function insert_row_failure_returns_null()
    {
        Http::fake([
            'https://example.supabase.co/rest/v1/*' => Http::response('', 500),
        ]);

        $svc = new SupabaseService();
        $result = $svc->insertRow('messages', ['a' => 1]);
        $this->assertNull($result);
    }

    /** @test */
    public function upload_buffer_failure_returns_false()
    {
        Http::fake([
            'https://example.supabase.co/storage/v1/object/*' => Http::response('', 500),
        ]);

        $svc = new SupabaseService();
        $ok = $svc->uploadBuffer('nextplot', 'path/file.jpg', 'bytes', 'image/jpeg');
        $this->assertFalse($ok);
    }

    /** @test */
    public function sign_path_failure_returns_null()
    {
        Http::fake([
            'https://example.supabase.co/storage/v1/object/sign/*' => Http::response('', 500),
        ]);

        $svc = new SupabaseService();
        $url = $svc->signPath('nextplot', 'path/file.jpg', 3600);
        $this->assertNull($url);
    }
}
