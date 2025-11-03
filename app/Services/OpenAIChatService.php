<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class OpenAIChatService implements ChatService
{
    private string $apiKey;
    private string $baseUrl;
    private string $model;
    private float $temperature;
    private int $maxTokens;
    private string $systemPrompt;

    public function __construct()
    {
        $cfg               = (array) config('nextplot.chat.openai', []);
        $this->apiKey      = (string) ($cfg['api_key'] ?? '');
        $this->baseUrl     = (string) ($cfg['base_url'] ?? 'https://api.openai.com/v1');
        $this->model       = (string) ($cfg['model'] ?? 'gpt-4o-mini');
        $this->temperature = (float) ($cfg['temperature'] ?? 0.3);
        $this->maxTokens   = (int)   ($cfg['max_tokens'] ?? 300);
        $this->systemPrompt= (string) ($cfg['system_prompt'] ?? '');
    }

    public function generate(string $prompt, array $context = []): ?string
    {
        if (empty($this->apiKey)) {
            Log::warning('[Chat] OpenAI API key not configured');
            return null;
        }

        try {
            $url = rtrim($this->baseUrl, '/') . '/chat/completions';

            $messages = [
                ['role' => 'system', 'content' => $this->systemPrompt],
                ['role' => 'user',   'content' => $prompt],
            ];

            $payload = [
                'model'       => $this->model,
                'messages'    => $messages,
                'temperature' => $this->temperature,
                'max_tokens'  => $this->maxTokens,
            ];

            $response = Http::withHeaders([
                'Authorization' => 'Bearer ' . $this->apiKey,
                'Content-Type'  => 'application/json',
            ])->post($url, $payload);

            if ($response->successful()) {
                $data = $response->json();
                $text = $data['choices'][0]['message']['content'] ?? null;
                if (is_string($text) && $text !== '') {
                    // LINE limit ~2000 chars; keep margin
                    return mb_substr($text, 0, 1800, 'UTF-8');
                }
            }

            Log::error('[Chat] OpenAI response failed', [
                'status' => $response->status(),
                'body'   => $response->body(),
            ]);
            return null;
        } catch (\Throwable $e) {
            Log::error('[Chat] OpenAI error', [
                'error' => $e->getMessage(),
            ]);
            return null;
        }
    }
}
