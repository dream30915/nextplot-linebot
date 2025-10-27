<?php

namespace Tests\Support;

use App\Services\NextPlotService;

class CountingNextPlotService extends NextPlotService
{
    public int $called = 0;

    public function __construct()
    {
        // no-op: avoid parent dependencies
    }

    public function processEvent(array $event): ?array
    {
        $this->called++;
        return null;
    }
}
