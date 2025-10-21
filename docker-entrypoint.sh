#!/bin/bash#!/bin/shset -ePORT=${PORT:-8080}# Best-effort permissions for Laravel writable dirsif [ -d /var/www/html/storage ]; then  chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache || true  chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache || truefi# Start PHP built-in server to serve the Laravel public directoryif [ -d /var/www/html/public ]; then  echo "Starting PHP built-in server on port ${PORT}, serving /var/www/html/public"  exec php -S 0.0.0.0:${PORT} -t /var/www/html/publicelse  echo "Warning: /var/www/html/public not found. Falling back to php-fpm"  exec php-fpm --nodaemonizefi
set -e

echo "🚀 Starting Laravel application..."

# Wait for environment variables
sleep 2

# Clear cached config
php artisan config:clear
php artisan cache:clear

# Verify APP_KEY
if [ -z "$APP_KEY" ]; then
    echo "❌ ERROR: APP_KEY not set!"
    exit 1
fi

echo "✅ APP_KEY configured"

# Cache configurations
php artisan config:cache
php artisan route:cache

echo "✅ Laravel configured"

# Configure Apache for Cloud Run
echo "🌐 Configuring Apache for PORT ${PORT:-8080}..."

# Set port (default 8080)
PORT="${PORT:-8080}"

# Enable mod_rewrite
a2enmod rewrite

# Update DocumentRoot to public/
sed -i 's|DocumentRoot /var/www/html|DocumentRoot /var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Update Directory directive
sed -i 's|<Directory /var/www/>|<Directory /var/www/html/public/>|g' /etc/apache2/apache2.conf
sed -i 's|AllowOverride None|AllowOverride All|g' /etc/apache2/apache2.conf

# Update VirtualHost port
sed -i "s|<VirtualHost \*:80>|<VirtualHost *:${PORT}>|g" /etc/apache2/sites-available/000-default.conf

# Update Listen port in ports.conf
sed -i "s|Listen 80|Listen ${PORT}|g" /etc/apache2/ports.conf

# Add ServerName to suppress warning
echo "ServerName localhost" >> /etc/apache2/apache2.conf

# Set file permissions
chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache
chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache

echo "✅ Apache configured to listen on PORT ${PORT}"
echo "🎯 Starting Apache..."

# Start Apache in foreground
exec apache2-foreground
