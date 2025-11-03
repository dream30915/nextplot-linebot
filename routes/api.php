<?php

use App\Http\Controllers\LineWebhookController;
use App\Http\Controllers\NextplotApiController;
use App\Http\Controllers\PropertySearchController;
use App\Http\Controllers\AggregatesController;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

// Health check endpoint
Route::get('/health', function () {
    $chatEnabled = (bool) config('nextplot.chat.enabled', false);
    $chatDriver  = (string) config('nextplot.chat.driver', 'none');
    $chatModel   = (string) config('nextplot.chat.openai.model', '');

    return response()->json([
        'status'    => 'healthy',
        'service'   => 'laravel',
        'timestamp' => now()->toIso8601String(),
        'version'   => app()->version(),
        'env'       => [
            'supabase' => config('services.supabase.url') ? 'configured' : 'missing',
            'line'     => config('services.line.channel_access_token') ? 'configured' : 'missing',
            'chat'     => [
                'enabled' => $chatEnabled,
                'driver'  => $chatDriver,
                'model'   => $chatModel,
            ],
        ],
    ]);
});

// health check / ping สำหรับสคริปต์ dev
Route::get('/nextplot/search', [NextplotApiController::class, 'search']);

// Aggregates for data-backed Q&A
Route::get('/nextplot/aggregates', [AggregatesController::class, 'summary']);

// Properties search (province/district/subdistrict/text)
Route::get('/nextplot/properties/search', [PropertySearchController::class, 'search']);

// LINE webhook endpoint
Route::post('/line/webhook', [LineWebhookController::class, 'handle']);
