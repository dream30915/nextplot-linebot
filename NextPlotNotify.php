<?php
namespace App\Services\NextPlot;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class NextPlotNotify
{
    protected $channelToken;
    protected $channelSecret;
    protected $allowlist;
}
