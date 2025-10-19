<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NextplotApiController extends Controller
{
    // GET /api/nextplot/search?q=ping
    public function search(Request $request): JsonResponse
    {
        $q = (string) $request->query('q', '');

        return response()->json([
            'ok'   => true,
            'q'    => $q,
            'time' => now()->toIso8601String(),
        ]);
    }
}