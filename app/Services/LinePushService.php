<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;

class LinePushService
{
    private string $baseUrl = 'https://api.line.me/v2/bot/message';
    private string $token;

    public function __construct()
    {
        $this->token = (string) env('LINE_CHANNEL_ACCESS_TOKEN', '');
    }

    public function enabled(): bool
    {
        return $this->token !== '';
    }

    /**
     * Push a simple text message to a userId.
     * Returns array with status info or throws on HTTP error when $throwOnError=true.
     */
    public function pushText(string $userId, string $text, bool $throwOnError = false): array
    {
        $payload = [
            'to' => $userId,
            'messages' => [
                [ 'type' => 'text', 'text' => mb_substr($text, 0, 5000) ],
            ],
        ];

        $resp = Http::withToken($this->token)
            ->acceptJson()
            ->asJson()
            ->post($this->baseUrl.'/push', $payload);

        if ($resp->failed()) {
            if ($throwOnError) {
                $resp->throw();
            }
            return [
                'ok' => false,
                'status' => $resp->status(),
                'body' => $resp->json() ?? $resp->body(),
            ];
        }

        return [ 'ok' => true, 'status' => $resp->status() ];
    }
}
