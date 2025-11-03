<?php

namespace App\Services;

interface ChatService
{
    /**
     * Generate a conversational reply.
     *
     * @param string $prompt User message in Thai/English
     * @param array<string,mixed> $context Optional lightweight context
     * @return string|null Reply text or null if not available
     */
    public function generate(string $prompt, array $context = []): ?string;
}
