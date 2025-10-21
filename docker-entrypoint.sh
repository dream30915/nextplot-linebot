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

# Set port from environment (Cloud Run uses PORT=8080)
PORT="${PORT:-8080}"
echo "📡 Configuring Apache to listen on PORT $PORT..."

# Enable rewrite module
a2enmod rewrite

# Update DocumentRoot to Laravel public directory
sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Update AllowOverride for .htaccess support
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf

# Update VirtualHost port
sed -i "s/<VirtualHost \*:80>/<VirtualHost *:${PORT}>/g" /etc/apache2/sites-available/000-default.conf

# Update Listen port
sed -i "s/Listen 80/Listen ${PORT}/g" /etc/apache2/ports.conf

# Set ServerName to suppress warning
echo "ServerName 127.0.0.1" >> /etc/apache2/apache2.conf

echo "✅ Apache configured to listen on PORT $PORT"

# Start Apache
exec apache2-foreground
