<?php

namespace App\Services;

class NlpSearch
{
    /**
     * @return array{sql:string, bindings: array<string, int|float|string>, explain:string}
     */
    public function toSql(string $q): array
    {
        $qNorm = mb_strtolower(trim($q), 'UTF-8');

        // ราคาไม่เกิน X ล้าน
        if (preg_match('/ราคา(ไม่เกิน|<=?)\s*(\d+)\s*ล้าน/u', $qNorm, $m)) {
            $limit = (int)$m[2] * 1_000_000;
            return [
                'sql'      => 'select * from properties where coalesce(price_total,0) <= :limit order by price_total asc',
                'bindings' => ['limit' => $limit],
                'explain'  => "ราคาไม่เกิน {$m[2]} ล้าน",
            ];
        }

        // WC มีทั้งหมดกี่ไร่
        if (preg_match('/\b([a-z]{1,10})\b.*(กี่ไร่|รวมกี่ไร่)/u', $qNorm, $m)) {
            $code = strtoupper($m[1]);
            return [
                'sql'      => 'select coalesce(sum(area_rai),0) as total_rai from properties where upper(code) = :code',
                'bindings' => ['code' => $code],
                'explain'  => "รวมพื้นที่ของโค้ด {$code}",
            ];
        }

        // ใกล้ชายหาด X กม. (ใช้ PostGIS)
        if (preg_match('/ใกล้(ชายหาด|ทะเล)\s*(\d+)\s*กม/u', $qNorm, $m)) {
            $km     = (int)$m[2];
            $meters = $km * 1000;
            $sql    = <<<SQL
select p.*
from properties p
join named_points np on np.slug = 'beach'
where p.lat is not null and p.lon is not null
  and ST_DistanceSphere(ST_SetSRID(ST_Point(p.lon, p.lat),4326), np.geom) <= :meters
order by price_total asc nulls last
SQL;
            return [
                'sql'      => $sql,
                'bindings' => ['meters' => $meters],
                'explain'  => "ใกล้ชายหาดไม่เกิน {$km} กม.",
            ];
        }

        // Fallback
        return [
            'sql'      => 'select * from properties order by created_at desc limit 50',
            'bindings' => [],
            'explain'  => 'ไม่เข้าใจคำถาม ใช้ 50 รายการล่าสุด',
        ];
    }
}
