# Use official PHP Apache image (works standalone on Cloud Run)
FROM php:8.2-apache

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

# Ensure entrypoint is executable (already copied in COPY . .)
RUN chmod +x /var/www/html/docker-entrypoint.sh && \
    cp /var/www/html/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# Set PORT environment variable
ENV PORT=8080

# Expose the port Cloud Run uses
EXPOSE 8080

# Use entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
