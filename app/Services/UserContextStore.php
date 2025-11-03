<?php

namespace App\Services;

interface UserContextStore
{
    /**
     * Load saved state for a context key.
     *
     * @return array<string, mixed>|null
     */
    public function load(string $contextKey): ?array;

    /**
     * Save state for a context key.
     *
     * @param array<string, mixed> $state
     */
    public function save(string $contextKey, array $state): void;

    /**
     * Clear state for a context key.
     */
    public function clear(string $contextKey): void;
}
