<?php

use Illuminate\Support\Facades\Route;
use App\Http\Controllers\ExportController;

Route::get('/healthz', function () {
    return response()->json([
        'ok'   => true,
        'time' => now()->toIso8601String(),
    ]);
});

Route::get('/', function () {
    return response('OK', 200);
});

// Simple dashboard (read-only)
Route::get('/dashboard', function () {
    $health = [
        'status' => 'unknown',
    ];
    try {
        $resp = \Illuminate\Support\Facades\Http::get(url('/api/health'));
        if ($resp->ok()) { $health = $resp->json(); }
    } catch (\Throwable $e) {
        $health = ['status' => 'error', 'message' => $e->getMessage()];
    }
    return view('dashboard', ['health' => $health]);
});

// Minimal export routes
Route::get('/export/csv', [ExportController::class, 'csv']);
Route::get('/export/pdf', [ExportController::class, 'pdf']);
