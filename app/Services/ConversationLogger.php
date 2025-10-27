<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class ConversationLogger
{
    private string $path;

    public function __construct(?string $path = null)
    {
        $this->path = $path ?: config('nextplot.logging.file', 'conversations.ndjson');
    }

    /**
     * @param array<string, mixed> $record
     */
    public function append(array $record): void
    {
        try {
            // Ensure storage path under local disk
            $line = json_encode([
                'ts'     => now()->toIso8601String(),
                'record' => $record,
            ], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";

            Storage::disk('local')->append($this->path, rtrim($line, "\n"));
        } catch (\Throwable $e) {
            Log::warning('[ConversationLogger] append failed', [
                'error' => $e->getMessage(),
            ]);
        }
    }
}
