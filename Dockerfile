# Use official PHP image
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
    && docker-php-ext-install pdo_mysql mbstring zip exif pcntl gd

# Install composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Copy composer files and install deps (use cache)
COPY composer.json composer.lock ./

# Copy application files BEFORE composer install (artisan needed for post-install scripts)
COPY . .

# Now run composer install (artisan file is now available)
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts

# Copy entrypoint and ensure executable
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Expose the port Cloud Run uses (if using built-in server)
EXPOSE 8080

# Use entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
