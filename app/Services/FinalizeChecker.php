<?php

namespace App\Services;

class FinalizeChecker
{
    public function check(array $payload): array
    {
        $code = trim((string)($payload['code'] ?? ''));
        $deed = trim((string)($payload['deed_no'] ?? ''));
        $text = (string)($payload['text'] ?? '');

        $status = 'pending';
        $notes = [];

        if ($code === '') {
            $status = 'draft';
            $notes[] = 'Missing CODE -> Draft';
        }

        if ($deed === '') {
            if (preg_match('/\bdeed\s+(\d+)\s*plots\b/i', $text)) {
                $status = 'pending-deedlist';
                $notes[] = 'Declared deed count but missing numbers -> Pending-DeedList';
            } else {
                $status = $status === 'draft' ? 'draft' : 'pending-ocr';
                $notes[] = 'Missing deed number -> Pending-OCR';
            }
        }

        if ($status === 'pending' && $code && $deed) {
            $status = 'finalized';
            $notes[] = 'Ready to finalize';
        }

        return ['status' => $status, 'notes' => $notes];
    }
}