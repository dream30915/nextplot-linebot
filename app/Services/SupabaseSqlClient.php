<?php
/*[{
	"resource": "/c:/Users/msi/Desktop/nextplot-linebot/app/Http/Controllers/LineWebhookController.php",
	"owner": "_generated_diagnostic_collection_name_#4",
	"code": "PHP6601",
	"severity": 2,
	"message": "Name '\\Throwable' can be simplified with 'Throwable'",
	"source": "PHP",
	"startLineNumber": 131,
	"startColumn": 18,
	"endLineNumber": 131,
	"endColumn": 28,
	"origin": "extHost1"
},{
	"resource": "/c:/Users/msi/Desktop/nextplot-linebot/app/Http/Controllers/LineWebhookController.php",
	"owner": "_generated_diagnostic_collection_name_#4",
	"code": "PHP6601",
	"severity": 2,
	"message": "Name '\\Throwable' can be simplified with 'Throwable'",
	"source": "PHP",
	"startLineNumber": 131,
	"startColumn": 18,
	"endLineNumber": 131,
	"endColumn": 28,
	"origin": "extHost1"
},{
	"resource": "/c:/Users/msi/Desktop/nextplot-linebot/app/Http/Controllers/LineWebhookController.php",
	"owner": "_generated_diagnostic_collection_name_#4",
	"code": "PHP6601",
	"severity": 2,
	"message": "Name '\\Throwable' can be simplified with 'Throwable'",
	"source": "PHP",
	"startLineNumber": 131,
	"startColumn": 18,
	"endLineNumber": 131,
	"endColumn": 28,
	"origin": "extHost1"
},{
	"resource": "/C:/Users/msi/Desktop/nextplot-linebot/app/Http/Controllers/LineWebhookController.php",
	"owner": "_generated_diagnostic_collection_name_#4",
	"code": "PHP6601",
	"severity": 2,
	"message": "Name '\\Throwable' can be simplified with 'Throwable'",
	"source": "PHP",
	"startLineNumber": 131,
	"startColumn": 18,
	"endLineNumber": 131,
	"endColumn": 28,
	"origin": "extHost1"
}]*/

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use RuntimeException;

class SupabaseSqlClient
{
	public function __construct(
		private readonly string $baseUrl,
		private readonly string $serviceKey,
	) {
	}

	public function isConfigured(): bool
	{
		return $this->baseUrl !== '' && $this->serviceKey !== '';
	}

	public function query(string $sql): array
	{
		if (! $this->isConfigured()) {
			throw new RuntimeException('Supabase credentials are not configured.');
		}

		$endpoint = rtrim($this->baseUrl, '/') . '/postgres/v1/query';

		$response = Http::withHeaders([
			'apikey' => $this->serviceKey,
			'Authorization' => 'Bearer ' . $this->serviceKey,
		])->acceptJson()->post($endpoint, [
			'query' => $sql,
		]);

		if (! $response->successful()) {
			Log::warning('Supabase SQL query failed', [
				'status' => $response->status(),
				'body' => $response->body(),
			]);

			throw new RuntimeException('Supabase query failed with status ' . $response->status());
		}

		$payload = $response->json();

		if (! is_array($payload)) {
			return [];
		}

		$data = $payload['data'] ?? null;

		return is_array($data) ? $data : [];
	}
}