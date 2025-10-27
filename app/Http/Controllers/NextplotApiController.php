<?php

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NextplotApiController extends Controller
{
    // GET /api/nextplot/search?q=ping
    public function search(Request $request): JsonResponse
    {
        $qRaw = $request->query('q');
        $q = is_string($qRaw) ? $qRaw : '';

        return response()->json([
            'ok'   => true,
            'q'    => $q,
            'time' => now()->toIso8601String(),
        ]);
    }
}
