<?php

namespace Tests\Feature;

use App\Services\FileUserContextStore;
use Tests\TestCase;

class UserContextStoreFileTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('filesystems.default', 'local');
    }

    /** @test */
    public function it_saves_and_loads_state()
    {
        $store = new FileUserContextStore();
        $key   = 'user:U_test_1';

        $state = ['code' => 'WC-007', 'deed' => 'โฉนด 8899'];
        $store->save($key, $state);

        $loaded = $store->load($key);
        $this->assertIsArray($loaded);
        $this->assertSame('WC-007', $loaded['code'] ?? null);
        $this->assertSame('โฉนด 8899', $loaded['deed'] ?? null);
    }

    /** @test */
    public function it_clears_state()
    {
        $store = new FileUserContextStore();
        $key   = 'user:U_test_2';

        $store->save($key, ['x' => 1]);
        $this->assertNotNull($store->load($key));

        $store->clear($key);
        $this->assertNull($store->load($key));
    }
}
