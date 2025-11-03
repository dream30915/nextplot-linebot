<?php

namespace App\Services;

/**
 * Stub service for OCR of deed numbers from images.
 * Implementation options:
 *  - Google Cloud Vision API (requires credentials)
 *  - Tesseract OCR (open-source, on-server)
 */
class OcrService
{
    public function extractDeedNumber(string $imagePathOrUrl): array
    {
        // TODO: Call OCR backend and parse Thai patterns like "โฉนด 8899"
        return [
            'ok' => false,
            'deed_number' => null,
            'hint' => 'OCR backend not configured yet',
        ];
    }
}
