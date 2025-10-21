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

echo "✅ Laravel configured successfully"

# Configure Apache for Cloud Run
echo "🌐 Configuring Apache..."
a2enmod rewrite
sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# Set port from environment (Cloud Run uses PORT=8080)
if [ ! -z "$PORT" ]; then
    sed -i "s/80/${PORT}/g" /etc/apache2/sites-available/000-default.conf /etc/apache2/ports.conf
fi

echo "✅ Apache configured"

# Start Apache
exec apache2-foreground
