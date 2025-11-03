<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Illuminate\Support\Facades\View;
use Dompdf\Dompdf;
use Dompdf\Options;

class ExportController extends Controller
{
    /**
     * Minimal CSV export (acts as Excel-friendly) with sample data.
     */
    public function csv(Request $request): StreamedResponse
    {
        $filename = 'nextplot-export.csv';
        $rows = [
            ['id','code','session','message','created_at'],
            ['1','WC-007','3','ตัวอย่างข้อความ','2025-10-31T12:00:00Z'],
        ];

        $callback = function () use ($rows) {
            $out = fopen('php://output', 'w');
            foreach ($rows as $r) {
                fputcsv($out, $r);
            }
            fclose($out);
        };

        return response()->stream($callback, 200, [
            'Content-Type' => 'text/csv; charset=UTF-8',
            'Content-Disposition' => "attachment; filename=\"$filename\"",
        ]);
    }

    /**
     * PDF export using dompdf if available; otherwise returns 501 with guidance.
     */
    public function pdf(Request $request)
    {
        // Minimal sample data; replace with real query later
        $data = [
            'title' => 'NextPlot Export',
            'generated_at' => now()->toIso8601String(),
            'rows' => [
                ['id' => 1, 'code' => 'WC-007', 'session' => 3, 'message' => 'ตัวอย่างข้อความ', 'created_at' => '2025-10-31T12:00:00Z'],
            ],
        ];

        // Render Blade to HTML
        $html = View::make('exports.sample', $data)->render();

        // Configure Dompdf
        $options = new Options();
        $options->set('isRemoteEnabled', true);
        $options->set('defaultFont', 'DejaVu Sans');
        $dompdf = new Dompdf($options);
        $dompdf->loadHtml($html, 'UTF-8');
        $dompdf->setPaper('A4', 'portrait');
        $dompdf->render();

        $pdfOutput = $dompdf->output();
        $filename = 'nextplot-export.pdf';

        return response()->streamDownload(function () use ($pdfOutput) {
            echo $pdfOutput;
        }, $filename, [
            'Content-Type' => 'application/pdf',
        ]);
    }
}
