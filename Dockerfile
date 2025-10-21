# Use official PHP 8.2 FPM image
FROM php:8.2-fpm

# Set working directory
WORKDIR /var/www/html

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    libpng-dev \
    libonig-dev \
    zip \
    procps \
  && docker-php-ext-install pdo_mysql mbstring zip exif pcntl gd

# Install composer (copy from official composer image)
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy application files first so artisan exists for composer scripts
COPY . .

# Install PHP dependencies without dev and non-interactive
# Use --no-scripts to avoid running artisan during build if artisan requires runtime environment
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts || true

# Ensure entrypoint is present, executable and owned by www-data
# If docker-entrypoint.sh is at repo root and copied by COPY . . above, set perms
RUN if [ -f ./docker-entrypoint.sh ]; then \
      mv ./docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh; \
      chmod +x /usr/local/bin/docker-entrypoint.sh; \
      chown www-data:www-data /usr/local/bin/docker-entrypoint.sh; \
    fi

# Set environment
ENV PORT=8080
EXPOSE 8080

# Ensure storage directories exist and ownership set
RUN mkdir -p storage/framework/{cache,sessions,views} bootstrap/cache \
  && chown -R www-data:www-data storage bootstrap/cache || true

# Final entrypoint: start php-fpm
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command (if entrypoint script uses exec to run php-fpm)
CMD ["php-fpm"]
