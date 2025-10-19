<?php

use Illuminate\Support\Facades\Route;

Route::get('/healthz', function () {
    return response()->json([
        'ok'   => true,
        'time' => now()->toIso8601String(),
    ]);
});