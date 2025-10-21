<?php

namespace App\Providers;

use App\Services\SupabaseSqlClient;
use App\Services\SupabaseService;
use App\Services\NextPlotService;
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
                $config['url'] ?? '',
                $config['service_role_key'] ?? '',
            );
        });

        // Register SupabaseService (required by NextPlotService)
        $this->app->singleton(SupabaseService::class, function ($app) {
            return new SupabaseService();
        });

        // Register NextPlotService (depends on SupabaseService)
        $this->app->singleton(NextPlotService::class, function ($app) {
            return new NextPlotService($app->make(SupabaseService::class));
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
