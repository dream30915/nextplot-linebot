<?php

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Route;
use App\Http\Controllers\NextplotApiController;
use App\Http\Controllers\LineWebhookController;

Route::get('/user', function (Request $request) {
    return $request->user();
})->middleware('auth:sanctum');

// health check / ping สำหรับสคริปต์ dev
Route::get('/nextplot/search', [NextplotApiController::class, 'search']);

// LINE webhook endpoint
Route::post('/line/webhook', [LineWebhookController::class, 'handle']);