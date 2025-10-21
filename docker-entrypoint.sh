#!/bin/bash
set -e

echo "๐€ Starting Laravel application..."

# Wait a moment for environment variables to be available
sleep 2

# Clear any cached config from build time
php artisan config:clear
php artisan cache:clear

# Verify APP_KEY is set
if [ -z "$APP_KEY" ]; then
    echo "โ ERROR: APP_KEY not set!"
    exit 1
fi

echo "โ… APP_KEY is configured"

# Cache configurations for better performance (now with env vars available)
php artisan config:cache
php artisan route:cache

echo "โ… Laravel configured successfully"

# Start PHP-FPM
exec php-fpm
