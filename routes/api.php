<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\NextplotApiController;
use App\Http\Controllers\LineWebhookController;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

// Health check endpoint
Route::get('/health', function () {
    return response()->json([
        'status' => 'healthy',
        'service' => 'laravel',
        'timestamp' => now()->toIso8601String(),
        'version' => app()->version(),
        'env' => [
            'supabase' => config('services.supabase.url') ? 'configured' : 'missing',
            'line' => config('services.line.channel_access_token') ? 'configured' : 'missing',
        ]
    ]);
});

// health check / ping สำหรับสคริปต์ dev
Route::get('/nextplot/search', [NextplotApiController::class, 'search']);

// LINE webhook endpoint
Route::post('/line/webhook', [LineWebhookController::class, 'handle']);