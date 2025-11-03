<?php

namespace App\Providers;

use App\Services\ConversationLogger;
use App\Services\NextPlotService;
use App\Services\UserContextStore;
use App\Services\FileUserContextStore;
use App\Services\SupabaseService;
use App\Services\SupabaseSqlClient;
use App\Services\ChatService;
use App\Services\OpenAIChatService;
use App\Services\NullChatService;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        // Register SupabaseSqlClient
        $this->app->singleton(SupabaseSqlClient::class, function ($app) {
            $config = $app['config']->get('services.supabase', []);

            return new SupabaseSqlClient(
                $config['url']              ?? '',
                $config['service_role_key'] ?? '',
            );
        });

        // Register SupabaseService (required by NextPlotService)
        $this->app->singleton(SupabaseService::class, function ($app) {
            return new SupabaseService();
        });

        // Register ConversationLogger
        $this->app->singleton(ConversationLogger::class, function ($app) {
            return new ConversationLogger();
        });

        // Bind UserContextStore based on config driver
        $this->app->singleton(UserContextStore::class, function ($app) {
            $driver = (string) ($app['config']->get('nextplot.context.driver', 'file'));
            switch ($driver) {
                case 'file':
                default:
                    return new FileUserContextStore();
            }
        });

        // Bind ChatService based on config
        $this->app->singleton(ChatService::class, function ($app) {
            $enabled = (bool) ($app['config']->get('nextplot.chat.enabled', false));
            $driver  = (string) ($app['config']->get('nextplot.chat.driver', 'none'));
            if (!$enabled || $driver === 'none') {
                return new NullChatService();
            }
            switch ($driver) {
                case 'openai':
                    return new OpenAIChatService();
                default:
                    return new NullChatService();
            }
        });

        // Register NextPlotService (depends on SupabaseService, UserContextStore, ChatService)
        $this->app->singleton(NextPlotService::class, function ($app) {
            return new NextPlotService(
                $app->make(SupabaseService::class),
                $app->make(ConversationLogger::class),
                $app->make(UserContextStore::class),
                $app->make(ChatService::class),
            );
        });
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
