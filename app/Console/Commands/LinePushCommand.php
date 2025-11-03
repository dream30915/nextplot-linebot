<?php

namespace App\Console\Commands;

use App\Services\LinePushService;
use Illuminate\Console\Command;

class LinePushCommand extends Command
{
    /**
     * The name and signature of the console command.
     * Usage: php artisan line:push {userId} {text*}
     */
    protected $signature = 'line:push {userId} {text*}';

    /**
     * The console command description.
     */
    protected $description = 'Send a LINE push message to a specific userId';

    public function handle(LinePushService $push): int
    {
        if (!$push->enabled()) {
            $this->error('LINE_CHANNEL_ACCESS_TOKEN is not set');
            return self::FAILURE;
        }

        $userId = (string) $this->argument('userId');
        $textParts = (array) $this->argument('text');
        $text = trim(implode(' ', $textParts));
        if ($userId === '' || $text === '') {
            $this->error('userId and text are required');
            return self::FAILURE;
        }

        $res = $push->pushText($userId, $text);
        if (!($res['ok'] ?? false)) {
            $this->error('Push failed: status '.$res['status'].' body='.json_encode($res['body'] ?? null));
            return self::FAILURE;
        }

        $this->info('Push sent (status '.$res['status'].')');
        return self::SUCCESS;
    }
}
