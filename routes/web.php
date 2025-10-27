<?php

use Illuminate\Support\Facades\Route;

Route::get('/healthz', function () {
    return response()->json([
        'ok'   => true,
        'time' => now()->toIso8601String(),
    ]);
});

Route::get('/', function () {
    return response('OK', 200);
});