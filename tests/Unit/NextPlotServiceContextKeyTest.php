<?php

namespace Tests\Unit;

use App\Services\ConversationLogger;
use App\Services\NextPlotService;
use App\Services\SupabaseService;
use App\Services\UserContextStore;
use Tests\TestCase;

class NextPlotServiceContextKeyTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('filesystems.default', 'local');
    }

    /** @test */
    public function it_uses_group_key_in_chat_scope()
    {
        config()->set('nextplot.context.scope', 'chat');

        $fakeStore = new class implements UserContextStore {
            public string $lastKey = '';
            public function load(string $contextKey): ?array { $this->lastKey = $contextKey; return ['code' => 'WC-007']; }
            public function save(string $contextKey, array $state): void { $this->lastKey = $contextKey; }
            public function clear(string $contextKey): void { $this->lastKey = $contextKey; }
        };

        $service = new NextPlotService(new SupabaseService(), new ConversationLogger(), $fakeStore);

        $event = [
            'type' => 'message',
            'source' => ['groupId' => 'G123', 'userId' => 'U1'],
            'message' => ['type' => 'text', 'id' => 'm1', 'text' => 'ต่อจากเดิม'],
        ];

        $reply = $service->processEvent($event);

        $this->assertIsArray($reply);
        $this->assertStringContainsString('CODE: WC-007', $reply['text'] ?? '');
        $this->assertSame('group:G123', $fakeStore->lastKey);
    }

    /** @test */
    public function it_uses_user_key_in_user_scope()
    {
        config()->set('nextplot.context.scope', 'user');

        $fakeStore = new class implements UserContextStore {
            public string $lastKey = '';
            public function load(string $contextKey): ?array { $this->lastKey = $contextKey; return ['code' => 'AB-123']; }
            public function save(string $contextKey, array $state): void { $this->lastKey = $contextKey; }
            public function clear(string $contextKey): void { $this->lastKey = $contextKey; }
        };

        $service = new NextPlotService(new SupabaseService(), new ConversationLogger(), $fakeStore);

        $event = [
            'type' => 'message',
            'source' => ['groupId' => 'G123', 'userId' => 'U1'],
            'message' => ['type' => 'text', 'id' => 'm1', 'text' => 'ต่อจากเดิม'],
        ];

        $reply = $service->processEvent($event);

        $this->assertIsArray($reply);
        $this->assertStringContainsString('CODE: AB-123', $reply['text'] ?? '');
        $this->assertSame('user:U1', $fakeStore->lastKey);
    }
}
