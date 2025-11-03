<?php

namespace Tests\Unit;

use App\Services\ChatService;
use App\Services\ConversationLogger;
use App\Services\NextPlotService;
use App\Services\SupabaseService;
use App\Services\UserContextStore;
use Tests\TestCase;

class NextPlotServiceChatTest extends TestCase
{
    protected function setUp(): void
    {
        parent::setUp();
        config()->set('filesystems.default', 'local');
    }

    /** @test */
    public function it_uses_ai_chat_when_no_structured_data_and_no_smalltalk_intent()
    {
        // Fake context store
        $fakeStore = new class implements UserContextStore {
            public array $saved = [];
            public function load(string $contextKey): ?array { return []; }
            public function save(string $contextKey, array $state): void { $this->saved[$contextKey] = $state; }
            public function clear(string $contextKey): void {}
        };

        // Fake ChatService returning a deterministic response
        $fakeChat = new class implements ChatService {
            public function generate(string $prompt, array $context = []): ?string
            {
                return 'นี่คือคำตอบเชิงสนทนาจาก AI';
            }
        };

        $service = new NextPlotService(new SupabaseService(), new ConversationLogger(), $fakeStore, $fakeChat);

        $event = [
            'type' => 'message',
            'source' => ['userId' => 'U1'],
            'message' => ['type' => 'text', 'id' => 'm1', 'text' => 'เล่าเรื่องให้ฟังหน่อย'],
        ];

        $reply = $service->processEvent($event);

        $this->assertIsArray($reply);
        $this->assertSame('text', $reply['type'] ?? '');
        $this->assertStringContainsString('คำตอบเชิงสนทนา', $reply['text'] ?? '');
    }
}
