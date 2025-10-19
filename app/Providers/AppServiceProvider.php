<?php

namespace App\Providers;

use App\Services\SupabaseSqlClient;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->singleton(SupabaseSqlClient::class, function ($app) {
            $config = $app['config']->get('services.supabase', []);

            return new SupabaseSqlClient(
                $config['url'] ?? '',
                $config['service_role_key'] ?? '',
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
