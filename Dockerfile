# Inherit from Heroku's stack
FROM heroku/heroku:16

# Internally, we arbitrarily use port 3000
ENV PORT 3000

# Which versions?
ENV PHP_VERSION 7.1.3
ENV REDIS_EXT_VERSION 3.1.2
ENV HTTPD_VERSION 2.4.20
ENV NGINX_VERSION 1.8.1
ENV NODE_ENGINE 6.11.1
ENV COMPOSER_VERSION 1.4.1

# Create some needed directories
RUN mkdir -p /app/.heroku/php /app/.heroku/node /app/.profile.d
WORKDIR /app/user

# Locate our binaries
ENV PATH /app/.heroku/php/bin:/app/.heroku/php/sbin:/app/.heroku/node/bin/:/app/user/node_modules/.bin:/app/user/vendor/bin:$PATH

# Install Apache
RUN curl --silent --location https://lang-php.s3.amazonaws.com/dist-heroku-16-stable/apache-$HTTPD_VERSION.tar.gz | tar xz -C /app/.heroku/php
# Config
RUN curl --silent --location https://raw.githubusercontent.com/heroku/heroku-buildpack-php/5a770b914549cf2a897cbbaf379eb5adf410d464/conf/apache2/httpd.conf.default > /app/.heroku/php/etc/apache2/httpd.conf
# FPM socket permissions workaround when run as root
RUN echo "\n\
Group root\n\
" >> /app/.heroku/php/etc/apache2/httpd.conf

# Install Nginx
RUN curl --silent --location https://lang-php.s3.amazonaws.com/dist-heroku-16-stable/nginx-$NGINX_VERSION.tar.gz | tar xz -C /app/.heroku/php
# Config
RUN curl --silent --location https://raw.githubusercontent.com/heroku/heroku-buildpack-php/5a770b914549cf2a897cbbaf379eb5adf410d464/conf/nginx/nginx.conf.default > /app/.heroku/php/etc/nginx/nginx.conf
# FPM socket permissions workaround when run as root
RUN echo "\n\
user nobody root;\n\
" >> /app/.heroku/php/etc/nginx/nginx.conf

# Install PHP
RUN curl --silent --location https://lang-php.s3.amazonaws.com/dist-heroku-16-stable/php-$PHP_VERSION.tar.gz | tar xz -C /app/.heroku/php
# Config
RUN mkdir -p /app/.heroku/php/etc/php/conf.d
RUN curl --silent --location https://raw.githubusercontent.com/heroku/heroku-buildpack-php/5a770b914549cf2a897cbbaf379eb5adf410d464/conf/php/php.ini > /app/.heroku/php/etc/php/php.ini
RUN curl --silent --location https://lang-php.s3.amazonaws.com/dist-heroku-16-stable/extensions/no-debug-non-zts-20160303/redis-$REDIS_EXT_VERSION.tar.gz | tar xz -C /app/.heroku/php
# Enable all optional exts
RUN echo "\n\
user_ini.cache_ttl = 30 \n\
opcache.enable = 0 \n\
extension=bcmath.so \n\
extension=calendar.so \n\
extension=exif.so \n\
extension=ftp.so \n\
extension=gd.so\n\
extension=gettext.so \n\
extension=mbstring.so \n\
extension=mcrypt.so \n\
extension=pcntl.so \n\
extension=redis.so \n\
extension=shmop.so \n\
extension=soap.so \n\
extension=sqlite3.so \n\
extension=pdo_sqlite.so \n\
extension=xmlrpc.so \n\
extension=xsl.so\n\
" >> /app/.heroku/php/etc/php/php.ini

# Install MySQL client
RUN apt-get update && apt-get install -y mysql-client

# Install Composer
RUN curl --silent --location https://lang-php.s3.amazonaws.com/dist-heroku-16-stable/composer-$COMPOSER_VERSION.tar.gz | tar xz -C /app/.heroku/php

# Install Node
RUN curl -s https://s3pository.heroku.com/node/v$NODE_ENGINE/node-v$NODE_ENGINE-linux-x64.tar.gz | tar --strip-components=1 -xz -C /app/.heroku/node

# copy dep files first so Docker caches the install step if they don't change
ONBUILD ADD composer.lock /app/user/
ONBUILD ADD composer.json /app/user/
# run install but without scripts as we don't have the app source yet
ONBUILD RUN composer install --no-scripts --no-suggest
# require the buildpack for execution
ONBUILD RUN composer show heroku/heroku-buildpack-php || { echo 'Your composer.json must have "heroku/heroku-buildpack-php" as a "require-dev" dependency.'; exit 1; }

# Run npm install if package.json is present
ONBUILD ADD package.json /app/user/
ONBUILD RUN /app/.heroku/node/bin/npm install

# rest of app
ONBUILD ADD . /app/user/
# run hooks
ONBUILD RUN cat composer.json | python -c 'import sys,json; sys.exit("post-install-cmd" not in json.load(sys.stdin).get("scripts", {}));' && composer run-script post-install-cmd || true
ONBUILD RUN cat composer.json | python -c 'import sys,json; sys.exit("post-autoload-dump" not in json.load(sys.stdin).get("scripts", {}));' && composer run-script post-autoload-dump || true
