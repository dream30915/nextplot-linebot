<?php

namespace App\Http\Controllers;

use App\Services\SupabaseSqlClient;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PropertySearchController extends Controller
{
    public function search(Request $request): JsonResponse
    {
        $baseUrl    = (string) config('nextplot.supabase.url', '');
        $serviceKey = (string) config('nextplot.supabase.service_role', '');

        $sql = new SupabaseSqlClient($baseUrl, $serviceKey);

        // Build filter
        $text       = trim((string) $request->query('text', ''));
        $province   = trim((string) $request->query('province', ''));
        $district   = trim((string) $request->query('district', ''));
        $subdistrict= trim((string) $request->query('subdistrict', ''));

        // Simple sanitize for single quotes
        $esc = function (string $v): string { return str_replace("'", "''", $v); };

        $wheres = [];
        if ($text !== '') {
            $t = $esc($text);
            $wheres[] = "(province ILIKE '%{$t}%' OR district ILIKE '%{$t}%' OR subdistrict ILIKE '%{$t}%' OR description ILIKE '%{$t}%' OR notes ILIKE '%{$t}%')";
        }
        if ($province !== '') { $wheres[] = "province ILIKE '%".$esc($province)."%'"; }
        if ($district !== '') { $wheres[] = "district ILIKE '%".$esc($district)."%'"; }
        if ($subdistrict !== '') { $wheres[] = "subdistrict ILIKE '%".$esc($subdistrict)."%'"; }

        $whereSql = count($wheres) ? ('WHERE ' . implode(' AND ', $wheres)) : '';

        $countSql = "SELECT COUNT(*) AS n FROM public.properties {$whereSql}";
        $rowsSql  = "SELECT id, code, deed_number, province, district, subdistrict, area_sqm, created_at, finalized_at FROM public.properties {$whereSql} ORDER BY COALESCE(finalized_at, created_at) DESC NULLS LAST LIMIT 20";

        try {
            $countRow = $sql->query($countSql)[0] ?? ['n' => 0];
            $rows     = $sql->query($rowsSql);
            $n        = (int) ($countRow['n'] ?? 0);

            return response()->json([
                'ok'   => true,
                'count'=> $n,
                'items'=> $rows,
            ]);
        } catch (\Throwable $e) {
            return response()->json([
                'ok'      => false,
                'error'   => 'search_failed',
                'message' => $e->getMessage(),
                'count'   => 0,
                'items'   => [],
            ], 200);
        }
    }
}
