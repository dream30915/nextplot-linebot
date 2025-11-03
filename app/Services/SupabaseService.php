<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Supabase Service
 * Translated from: line-webhook-proxy/lib/supabase.js
 *
 * Provides methods to interact with Supabase:
 * - insertRow: Insert data into PostgREST tables
 * - uploadBuffer: Upload files to Supabase Storage
 * - signPath: Generate signed URLs for private files
 * - ensureBucket: Create storage bucket if not exists
 */
class SupabaseService
{
    private string $supabaseUrl;
    private string $anonKey;
    private string $serviceRole;

    public function __construct()
    {
        $this->supabaseUrl = config('nextplot.supabase.url')          ?? '';
        $this->serviceRole = config('nextplot.supabase.service_role') ?? '';

        $anonKeyConfig = config('nextplot.supabase.anon_key');
        $this->anonKey = !empty($anonKeyConfig) ? $anonKeyConfig : $this->serviceRole;


        if (!$this->supabaseUrl || !$this->anonKey) {
            Log::warning('Supabase configuration missing critical values', [
                'url_set'          => !empty($this->supabaseUrl),
                'anon_key_set'     => !empty($anonKeyConfig),
                'service_role_set' => !empty($this->serviceRole),
            ]);
        }
    }

    /**
     * Record an event into public.events
     *
     * Contract:
     * - event_type: one of schema enums (e.g., 'message_received', 'media_uploaded', ...)
     * - data: JSON-serializable payload; include external identifiers like line_user_id
     * - user_id/property_id: optional UUIDs referencing members/properties
     *
     * @param string $eventType
     * @param array<string,mixed> $data
     * @param string|null $userId UUID of members.id (optional)
     * @param string|null $propertyId UUID of properties.id (optional)
     * @return array<string, mixed>|null
     */
    public function recordEvent(string $eventType, array $data, ?string $userId = null, ?string $propertyId = null): ?array
    {
        $payload = [
            'event_type'  => $eventType,
            'data'        => $data,
        ];

        if (!empty($userId)) {
            $payload['user_id'] = $userId;
        }
        if (!empty($propertyId)) {
            $payload['property_id'] = $propertyId;
        }

        return $this->insertRow('events', $payload);
    }

    /**
     * Create a new property
     *
     * @param array<string,mixed> $data
     * @return array<string,mixed>|null
     */
    public function createProperty(array $data): ?array
    {
        return $this->insertRow('properties', $data);
    }

    /**
     * Update an existing property by id
     *
     * @param string $id
     * @param array<string,mixed> $data
     * @return array<string,mixed>|null
     */
    public function updateProperty(string $id, array $data): ?array
    {
        try {
            $url = sprintf('%s/rest/v1/properties?id=eq.%s', $this->supabaseUrl, rawurlencode($id));

            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
                'Content-Type'  => 'application/json',
                'Prefer'        => 'return=representation',
            ])->patch($url, $data);

            if ($response->successful()) {
                $rows = $response->json();
                return $rows[0] ?? null;
            }

            Log::error('[Supabase] Update property failed', [
                'id'     => $id,
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return null;
        } catch (\Exception $e) {
            Log::error('[Supabase] Update property error', [
                'id'    => $id,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Finalize a property (status=finalized, set finalized_at)
     *
     * @param string $id
     * @return array<string,mixed>|null
     */
    public function finalizeProperty(string $id): ?array
    {
        $nowIso = gmdate('c');
        return $this->updateProperty($id, [
            'status'       => 'finalized',
            'finalized_at' => $nowIso,
        ]);
    }

    /**
     * Get property by id
     *
     * @param string $id
     * @return array<string,mixed>|null
     */
    public function getPropertyById(string $id): ?array
    {
        try {
            $url = sprintf('%s/rest/v1/properties?id=eq.%s&limit=1', $this->supabaseUrl, rawurlencode($id));
            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
            ])->get($url);

            if ($response->successful()) {
                $rows = $response->json();
                return $rows[0] ?? null;
            }

            Log::error('[Supabase] Get property failed', [
                'id'     => $id,
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return null;
        } catch (\Exception $e) {
            Log::error('[Supabase] Get property error', [
                'id'    => $id,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * List property summaries with optional filters
     * Supported filters: status, code, run_number, limit
     *
     * @param array<string,mixed> $filters
     * @return array<int, array<string,mixed>>
     */
    public function listPropertySummaries(array $filters = []): array
    {
        try {
            $query = ['select' => '*'];
            if (!empty($filters['status'])) {
                $query['status'] = 'eq.' . $filters['status'];
            }
            if (!empty($filters['code'])) {
                $query['code'] = 'eq.' . $filters['code'];
            }
            if (isset($filters['run_number'])) {
                $query['run_number'] = 'eq.' . (string)$filters['run_number'];
            }
            if (!empty($filters['limit'])) {
                $query['limit'] = (string) $filters['limit'];
            } else {
                $query['limit'] = '50';
            }

            $url = sprintf('%s/rest/v1/properties_summary?%s', $this->supabaseUrl, http_build_query($query));

            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
            ])->get($url);

            if ($response->successful()) {
                $rows = $response->json();
                return is_array($rows) ? $rows : [];
            }

            Log::error('[Supabase] List property summaries failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return [];
        } catch (\Exception $e) {
            Log::error('[Supabase] List property summaries error', [
                'error' => $e->getMessage(),
            ]);
            return [];
        }
    }

    /**
     * Insert a row into a Supabase table via PostgREST
     *
     * @param string $table Table name
    * @param array<string, mixed> $payload Data to insert
    * @return array<string, mixed>|null Inserted row or null on failure
     */
    public function insertRow(string $table, array $payload): ?array
    {
        try {
            $url = "{$this->supabaseUrl}/rest/v1/{$table}";

            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
                'Content-Type'  => 'application/json',
                'Prefer'        => 'return=representation',
            ])->post($url, $payload);

            if ($response->successful()) {
                $data = $response->json();
                Log::info("[Supabase] Inserted into {$table}", ['id' => $data[0]['id'] ?? 'unknown']);
                return $data[0] ?? null;
            }

            Log::error('[Supabase] Insert failed', [
                'table'  => $table,
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return null;

        } catch (\Exception $e) {
            Log::error('[Supabase] Insert error', [
                'table' => $table,
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Upload a file buffer to Supabase Storage
     *
     * @param string $bucket Bucket name
     * @param string $path File path in bucket (e.g., "line/2025/01/19/image.jpg")
     * @param string $buffer Binary file content
     * @param string $contentType MIME type
     * @return bool Success status
     */
    public function uploadBuffer(string $bucket, string $path, string $buffer, string $contentType): bool
    {
        try {
            $url = "{$this->supabaseUrl}/storage/v1/object/{$bucket}/{$path}";

            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
                'Content-Type'  => $contentType,
            ])->withBody($buffer, $contentType)->post($url);

            if ($response->successful()) {
                Log::info('[Supabase Storage] Uploaded file', [
                    'bucket' => $bucket,
                    'path'   => $path,
                    'size'   => strlen($buffer),
                ]);
                return true;
            }

            Log::error('[Supabase Storage] Upload failed', [
                'bucket' => $bucket,
                'path'   => $path,
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return false;

        } catch (\Exception $e) {
            Log::error('[Supabase Storage] Upload error', [
                'bucket' => $bucket,
                'path'   => $path,
                'error'  => $e->getMessage(),
            ]);
            return false;
        }
    }

    /**
     * Generate a signed URL for a private file
     *
     * @param string $bucket Bucket name
     * @param string $path File path in bucket
     * @param int $expiresIn Expiry time in seconds (default: 3600 = 1 hour)
     * @return string|null Signed URL or null on failure
     */
    public function signPath(string $bucket, string $path, int $expiresIn = 3600): ?string
    {
        try {
            $url = "{$this->supabaseUrl}/storage/v1/object/sign/{$bucket}/{$path}";

            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
                'Content-Type'  => 'application/json',
            ])->post($url, ['expiresIn' => $expiresIn]);

            if ($response->successful()) {
                $data       = $response->json();
                $signedPath = $data['signedURL'] ?? null;

                if ($signedPath) {
                    $fullUrl = "{$this->supabaseUrl}/storage/v1{$signedPath}";
                    Log::info('[Supabase Storage] Signed URL generated', [
                        'bucket'    => $bucket,
                        'path'      => $path,
                        'expiresIn' => $expiresIn,
                    ]);
                    return $fullUrl;
                }
            }

            Log::error('[Supabase Storage] Sign failed', [
                'bucket' => $bucket,
                'path'   => $path,
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return null;

        } catch (\Exception $e) {
            Log::error('[Supabase Storage] Sign error', [
                'bucket' => $bucket,
                'path'   => $path,
                'error'  => $e->getMessage(),
            ]);
            return null;
        }
    }

    /**
     * Ensure storage bucket exists (create if not)
     *
     * @param string $bucket Bucket name
     * @param bool $isPublic Whether bucket should be public
     * @return bool Success status
     */
    public function ensureBucket(string $bucket, bool $isPublic = false): bool
    {
        try {
            // Check if bucket exists
            $listUrl  = "{$this->supabaseUrl}/storage/v1/bucket";
            $response = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
            ])->get($listUrl);

            if ($response->successful()) {
                $buckets = $response->json();
                $exists  = false;
                if (is_array($buckets)) {
                    foreach ($buckets as $b) {
                        if (is_array($b) && ($b['name'] ?? null) === $bucket) {
                            $exists = true;
                            break;
                        }
                    }
                }

                if ($exists) {
                    Log::info('[Supabase Storage] Bucket exists', ['bucket' => $bucket]);
                    return true;
                }
            }

            // Create bucket
            $createUrl      = "{$this->supabaseUrl}/storage/v1/bucket";
            $createResponse = Http::withHeaders([
                'apikey'        => $this->anonKey,
                'Authorization' => "Bearer {$this->serviceRole}",
                'Content-Type'  => 'application/json',
            ])->post($createUrl, [
                'name'   => $bucket,
                'public' => $isPublic,
            ]);

            if ($createResponse->successful()) {
                Log::info('[Supabase Storage] Bucket created', [
                    'bucket' => $bucket,
                    'public' => $isPublic,
                ]);
                return true;
            }

            Log::error('[Supabase Storage] Bucket creation failed', [
                'bucket' => $bucket,
                'status' => $createResponse->status(),
                'body'   => $createResponse->body(),
            ]);
            return false;

        } catch (\Exception $e) {
            Log::error('[Supabase Storage] Bucket ensure error', [
                'bucket' => $bucket,
                'error'  => $e->getMessage(),
            ]);
            return false;
        }
    }
}
