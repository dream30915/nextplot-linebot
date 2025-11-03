<?php

namespace App\Services;

class NullChatService implements ChatService
{
    public function generate(string $prompt, array $context = []): ?string
    {
        return null;
    }
}
