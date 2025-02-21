FROM php:8.3-fpm AS php83

RUN  --mount=type=bind,from=mlocati/php-extension-installer:latest,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
      install-php-extensions apcu bcmath @composer curl dom exif gd imagick intl mysqli opcache pdo_mysql soap xml zip

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

FROM php:7.4-fpm AS php74

RUN  --mount=type=bind,from=mlocati/php-extension-installer:latest,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
      install-php-extensions apcu bcmath @composer curl dom exif gd imagick intl mysqli opcache pdo_mysql soap xml zip

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"