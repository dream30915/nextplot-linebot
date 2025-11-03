<?php

namespace App\Services;

use Illuminate\Support\Facades\Log;

class FileUserContextStore implements UserContextStore
{
    private string $dir = 'user_state';

    public function load(string $contextKey): ?array
    {
        try {
            $path = $this->fullPath($contextKey);
            if (!is_file($path)) {
                return null;
            }
            $json = @file_get_contents($path);
            if ($json === false) {
                return null;
            }
            $data = json_decode($json, true);
            return is_array($data) ? $data : null;
        } catch (\Throwable $e) {
            Log::warning('[UserContextStore:file] load failed', [
                'key' => $contextKey,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    public function save(string $contextKey, array $state): void
    {
        try {
            $path = $this->fullPath($contextKey);
            $this->ensureDir(dirname($path));
            $payload = json_encode($state, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
            $contents = ($payload === false) ? '{}' : $payload;
            // Write atomically when possible
            @file_put_contents($path, $contents, LOCK_EX);
        } catch (\Throwable $e) {
            Log::warning('[UserContextStore:file] save failed', [
                'key' => $contextKey,
                'error' => $e->getMessage(),
            ]);
        }
    }

    public function clear(string $contextKey): void
    {
        try {
            $path = $this->fullPath($contextKey);
            if (is_file($path)) {
                @unlink($path);
            }
        } catch (\Throwable $e) {
            Log::warning('[UserContextStore:file] clear failed', [
                'key' => $contextKey,
                'error' => $e->getMessage(),
            ]);
        }
    }

    private function fullPath(string $contextKey): string
    {
        $safe = rawurlencode($contextKey);
        $root = rtrim(storage_path('app'), DIRECTORY_SEPARATOR);
        return $root . DIRECTORY_SEPARATOR . $this->dir . DIRECTORY_SEPARATOR . $safe . '.json';
    }

    private function ensureDir(string $dir): void
    {
        if (!is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }
    }
}
