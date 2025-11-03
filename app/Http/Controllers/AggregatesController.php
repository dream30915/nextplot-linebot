<?php

namespace App\Http\Controllers;

use App\Services\SupabaseSqlClient;
use Illuminate\Http\JsonResponse;

class AggregatesController extends Controller
{
    public function summary(): JsonResponse
    {
        $baseUrl    = (string) config('nextplot.supabase.url', '');
        $serviceKey = (string) config('nextplot.supabase.service_role', '');

        // Graceful default when Supabase isn't configured
        if ($baseUrl === '' || $serviceKey === '') {
            return response()->json([
                'ok'         => true,
                'unavailable'=> true,
                'total'      => ['sqm' => 0, 'rai' => 0.0],
                'counts'     => ['properties' => 0, 'deeds' => 0],
                'top_finder' => null,
                'latest_plot'=> null,
            ]);
        }

        $sql = new SupabaseSqlClient($baseUrl, $serviceKey);

        // Prepare queries
        $qTotalSqm = "SELECT COALESCE(SUM(area_sqm), 0) AS total_sqm, COUNT(*) AS properties_count FROM public.properties WHERE area_sqm IS NOT NULL";
        $qDeeds    = "SELECT COUNT(*) AS deed_count FROM public.properties WHERE deed_number IS NOT NULL AND deed_number <> ''";
        $qTopFinder = <<<SQL
            SELECT m.id AS member_id, COALESCE(m.display_name, '') AS name, COUNT(*) AS cnt
            FROM public.properties p
            JOIN public.members m ON p.referred_by = m.id
            GROUP BY m.id, m.display_name
            ORDER BY cnt DESC NULLS LAST
            LIMIT 1
        SQL;
        $qLatest = "SELECT id, code, deed_number, created_at, finalized_at, province, district FROM public.properties ORDER BY COALESCE(finalized_at, created_at) DESC NULLS LAST LIMIT 1";

        try {
            $totalRow = $sql->query($qTotalSqm)[0] ?? ['total_sqm' => 0, 'properties_count' => 0];
            $deedRow  = $sql->query($qDeeds)[0]     ?? ['deed_count' => 0];
            $topRow   = $sql->query($qTopFinder)[0] ?? null;
            $latest   = $sql->query($qLatest)[0]    ?? null;

            $totalSqm = (float) ($totalRow['total_sqm'] ?? 0);
            $propertiesCount = (int) ($totalRow['properties_count'] ?? 0);
            $deedCount = (int) ($deedRow['deed_count'] ?? 0);
            $rai = $totalSqm > 0 ? round($totalSqm / 1600, 2) : 0.0;

            $topFinder = $topRow ? [
                'member_id' => $topRow['member_id'] ?? null,
                'name'      => $topRow['name'] ?? null,
                'count'     => isset($topRow['cnt']) ? (int) $topRow['cnt'] : null,
            ] : null;

            return response()->json([
                'ok'     => true,
                'total'  => [
                    'sqm' => $totalSqm,
                    'rai' => $rai,
                ],
                'counts' => [
                    'properties' => $propertiesCount,
                    'deeds'      => $deedCount,
                ],
                'top_finder' => $topFinder,
                'latest_plot'=> $latest,
            ]);
        } catch (\Throwable $e) {
            // Graceful failure with stable response shape
            return response()->json([
                'ok'          => false,
                'unavailable' => true,
                'error'       => 'aggregate_query_failed',
                'message'     => 'Unable to query aggregates right now',
                'total'       => ['sqm' => 0, 'rai' => 0.0],
                'counts'      => ['properties' => 0, 'deeds' => 0],
                'top_finder'  => null,
                'latest_plot' => null,
            ], 200);
        }
    }
}
