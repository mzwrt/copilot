# =======================================================
# PHP-FPM Docker 构建文件
# 基于源码编译 PHP-FPM，安全加固配置
# 符合 CIS Docker Benchmark 安全基准
# =======================================================
#
# 构建示例:
#   docker build -t php-fpm .
#   docker build --build-arg PHP_VERSION=8.4.4 -t php-fpm .
#   docker build --build-arg USE_redis=false -t php-fpm .
#
# 运行示例:
#   docker run -d --name php-fpm php-fpm
#   docker compose up -d
#

###############################################
# 第三方扩展开关 (Extension Toggles)
# 设置为 "true" 启用，"false" 禁用
# 构建时可通过 --build-arg 覆盖
###############################################

# Redis 扩展
ARG USE_redis=true

# Memcached 扩展
ARG USE_memcached=true

# ImageMagick 扩展 (imagick)
ARG USE_imagick=true

# MongoDB 扩展
ARG USE_mongodb=false

# Swoole 扩展
ARG USE_swoole=false

# OPcache 扩展（强烈推荐启用）
ARG USE_opcache=true

# Snuffleupagus 安全扩展（PHP 安全加固模块，运行时防护）
ARG USE_snuffleupagus=false

###############################################
# 版本配置 (Version Configuration)
# 留空 "" 表示自动获取最新版本
# 填写具体版本号表示使用指定版本
# 构建时可通过 --build-arg 覆盖
###############################################

# PHP 版本（必须手动指定）
ARG PHP_VERSION=8.4.4

# Redis 扩展版本（留空自动获取最新版）
ARG REDIS_VERSION=""

# Memcached 扩展版本（留空自动获取最新版）
ARG MEMCACHED_VERSION=""

# ImageMagick 扩展版本（留空自动获取最新版）
ARG IMAGICK_VERSION=""

# MongoDB 扩展版本（留空自动获取最新版）
ARG MONGODB_VERSION=""

# Swoole 扩展版本（留空自动获取最新版）
ARG SWOOLE_VERSION=""

# Snuffleupagus 安全扩展版本（留空使用最新版）
ARG SNUFFLEUPAGUS_VERSION=""

###############################################
# 额外 PHP 扩展入口 (Extra PHP Extensions)
# 可添加额外的 --enable 或 --with 参数
# 多个参数用空格分隔
###############################################
ARG EXTRA_PHP_EXTENSIONS=""

# =======================================================
# Stage 1: 编译阶段 (Build Stage)
# 使用完整 Debian 进行编译，最终镜像只保留运行时文件
# =======================================================
FROM debian:bookworm-slim AS builder

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明所有 ARGs（FROM 之后 ARG 需要重新声明）
ARG USE_redis
ARG USE_memcached
ARG USE_imagick
ARG USE_mongodb
ARG USE_swoole
ARG USE_opcache
ARG USE_snuffleupagus
ARG PHP_VERSION
ARG REDIS_VERSION
ARG MEMCACHED_VERSION
ARG IMAGICK_VERSION
ARG MONGODB_VERSION
ARG SWOOLE_VERSION
ARG SNUFFLEUPAGUS_VERSION
ARG EXTRA_PHP_EXTENSIONS

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_DIR=/opt/php \
    PHP_SRC_DIR=/opt/php/src

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    re2c \
    bison \
    pkg-config \
    wget \
    curl \
    ca-certificates \
    git \
    libxml2-dev \
    libsqlite3-dev \
    libssl-dev \
    zlib1g-dev \
    libcurl4-openssl-dev \
    libpng-dev \
    libjpeg62-turbo-dev \
    libfreetype6-dev \
    libwebp-dev \
    libavif-dev \
    libonig-dev \
    libzip-dev \
    libsodium-dev \
    libargon2-dev \
    libreadline-dev \
    libxslt1-dev \
    libbz2-dev \
    libgmp-dev \
    libldap2-dev \
    libpq-dev \
    libmemcached-dev \
    libmagickwand-dev \
    libicu-dev \
    libevent-dev \
    libtidy-dev \
    && rm -rf /var/lib/apt/lists/*

# 创建构建目录
RUN mkdir -p ${PHP_SRC_DIR} \
    && chmod 750 ${PHP_SRC_DIR} \
    && chown root:root ${PHP_SRC_DIR}

# 下载 PHP 源码
RUN cd ${PHP_SRC_DIR} \
    && wget --tries=5 --waitretry=2 --no-check-certificate \
       "https://www.php.net/distributions/php-${PHP_VERSION}.tar.gz" \
    && tar -zxf "php-${PHP_VERSION}.tar.gz" \
    && mv "php-${PHP_VERSION}" php \
    && rm -f "php-${PHP_VERSION}.tar.gz" \
    && chown -R root:root ${PHP_SRC_DIR}/php

# 配置、编译、安装 PHP
RUN set -eux; \
    cd ${PHP_SRC_DIR}/php; \
    EXTRA_ARGS=""; \
    if [ "${USE_opcache}" = "true" ]; then \
      EXTRA_ARGS="$EXTRA_ARGS --enable-opcache"; \
    fi; \
    if [ -n "${EXTRA_PHP_EXTENSIONS}" ]; then \
      EXTRA_ARGS="$EXTRA_ARGS ${EXTRA_PHP_EXTENSIONS}"; \
    fi; \
    ./configure \
      --prefix=${PHP_DIR} \
      --with-config-file-path=${PHP_DIR}/etc \
      --with-config-file-scan-dir=${PHP_DIR}/etc/conf.d \
      --enable-fpm \
      --with-fpm-user=www-data \
      --with-fpm-group=www-data \
      --enable-mysqlnd \
      --with-mysqli=mysqlnd \
      --with-pdo-mysql=mysqlnd \
      --with-pgsql \
      --with-pdo-pgsql \
      --with-openssl \
      --with-zlib \
      --with-curl \
      --enable-gd \
      --with-jpeg \
      --with-freetype \
      --with-webp \
      --with-avif \
      --with-zip \
      --with-sodium \
      --with-password-argon2 \
      --with-readline \
      --with-xsl \
      --with-bz2 \
      --with-gmp \
      --with-ldap \
      --with-gettext \
      --with-mhash \
      --with-tidy \
      --enable-mbstring \
      --enable-intl \
      --enable-bcmath \
      --enable-calendar \
      --enable-exif \
      --enable-ftp \
      --enable-pcntl \
      --enable-shmop \
      --enable-soap \
      --enable-sockets \
      --enable-sysvmsg \
      --enable-sysvsem \
      --enable-sysvshm \
      $EXTRA_ARGS; \
    make -j$(nproc); \
    make install

# 安装 PECL 扩展
# Redis 扩展
RUN set -eux; \
    if [ "${USE_redis}" = "true" ]; then \
      if [ -n "${REDIS_VERSION}" ]; then \
        ${PHP_DIR}/bin/pecl install "redis-${REDIS_VERSION}"; \
      else \
        ${PHP_DIR}/bin/pecl install redis; \
      fi; \
    fi

# Memcached 扩展
RUN set -eux; \
    if [ "${USE_memcached}" = "true" ]; then \
      if [ -n "${MEMCACHED_VERSION}" ]; then \
        ${PHP_DIR}/bin/pecl install "memcached-${MEMCACHED_VERSION}"; \
      else \
        ${PHP_DIR}/bin/pecl install memcached; \
      fi; \
    fi

# ImageMagick 扩展
RUN set -eux; \
    if [ "${USE_imagick}" = "true" ]; then \
      if [ -n "${IMAGICK_VERSION}" ]; then \
        ${PHP_DIR}/bin/pecl install "imagick-${IMAGICK_VERSION}"; \
      else \
        ${PHP_DIR}/bin/pecl install imagick; \
      fi; \
    fi

# MongoDB 扩展
RUN set -eux; \
    if [ "${USE_mongodb}" = "true" ]; then \
      if [ -n "${MONGODB_VERSION}" ]; then \
        ${PHP_DIR}/bin/pecl install "mongodb-${MONGODB_VERSION}"; \
      else \
        ${PHP_DIR}/bin/pecl install mongodb; \
      fi; \
    fi

# Swoole 扩展
RUN set -eux; \
    if [ "${USE_swoole}" = "true" ]; then \
      if [ -n "${SWOOLE_VERSION}" ]; then \
        ${PHP_DIR}/bin/pecl install "swoole-${SWOOLE_VERSION}"; \
      else \
        ${PHP_DIR}/bin/pecl install swoole; \
      fi; \
    fi

# Snuffleupagus 安全扩展（PHP 运行时安全加固）
RUN set -eux; \
    if [ "${USE_snuffleupagus}" = "true" ]; then \
      cd ${PHP_SRC_DIR}; \
      if [ -n "${SNUFFLEUPAGUS_VERSION}" ]; then \
        git clone --depth 1 -b "v${SNUFFLEUPAGUS_VERSION}" \
          https://github.com/jvoisin/snuffleupagus.git; \
      else \
        git clone --depth 1 https://github.com/jvoisin/snuffleupagus.git; \
      fi; \
      cd snuffleupagus/src; \
      ${PHP_DIR}/bin/phpize; \
      ./configure --with-php-config=${PHP_DIR}/bin/php-config; \
      make -j$(nproc); \
      make install; \
    fi

# 清理源码目录以减小镜像体积
RUN rm -rf ${PHP_SRC_DIR}


# =======================================================
# Stage 2: 运行阶段 (Runtime Stage)
# CIS Docker Benchmark 合规 - 最小化镜像
# =======================================================
FROM debian:bookworm-slim

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OCI 镜像标签（用于 Docker Hub 展示）
LABEL org.opencontainers.image.title="PHP-FPM" \
      org.opencontainers.image.description="Security-hardened PHP-FPM compiled from source, CIS Docker Benchmark compliant" \
      org.opencontainers.image.source="https://github.com/mzwrt/copilot" \
      org.opencontainers.image.licenses="MIT"

# 重新声明运行时需要的 ARGs
ARG USE_redis
ARG USE_memcached
ARG USE_imagick
ARG USE_mongodb
ARG USE_swoole
ARG USE_opcache
ARG USE_snuffleupagus

ENV DEBIAN_FRONTEND=noninteractive \
    PHP_DIR=/opt/php \
    PATH="/opt/php/bin:/opt/php/sbin:${PATH}"

# CIS Docker 4.1 - 创建非 root 运行用户
RUN groupadd -r www-data 2>/dev/null || true \
    && useradd -r -g www-data -s /sbin/nologin -d /nonexistent www-data 2>/dev/null || true

# CIS Docker 4.3 - 仅安装必要的运行时依赖（最小化）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libxml2 \
    libsqlite3-0 \
    libssl3 \
    zlib1g \
    libcurl4 \
    libpng16-16 \
    libjpeg62-turbo \
    libfreetype6 \
    libwebp7 \
    libavif15 \
    libonig5 \
    libzip4 \
    libsodium23 \
    libargon2-1 \
    libreadline8 \
    libxslt1.1 \
    libbz2-1.0 \
    libgmp10 \
    libldap-2.5-0 \
    libpq5 \
    libmemcached11 \
    libmagickwand-6.q16-6 \
    libicu72 \
    libevent-2.1-7 \
    libtidy5deb1 \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# CIS Docker 4.8 - 移除不必要的 setuid/setgid 权限
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# 从编译阶段复制 PHP 安装文件
COPY --from=builder /opt/php /opt/php

# 创建目录结构
RUN mkdir -p \
    ${PHP_DIR}/etc/conf.d \
    ${PHP_DIR}/var/log \
    ${PHP_DIR}/var/run \
    /www/wwwroot/html \
    /tmp/php-session \
    /tmp/php-upload

# ============================================================
# 复制本地配置文件
# ============================================================

# 复制 PHP 配置文件
COPY conf/php.ini ${PHP_DIR}/etc/php.ini
COPY conf/php-fpm.conf ${PHP_DIR}/etc/php-fpm.conf
COPY conf/www.conf ${PHP_DIR}/etc/php-fpm.d/www.conf

# 根据编译选项条件性启用扩展配置
RUN set -eux; \
    if [ "${USE_opcache}" = "true" ]; then \
      echo "zend_extension=opcache.so" > ${PHP_DIR}/etc/conf.d/10-opcache.ini; \
    fi; \
    if [ "${USE_redis}" = "true" ]; then \
      echo "extension=redis.so" > ${PHP_DIR}/etc/conf.d/20-redis.ini; \
    fi; \
    if [ "${USE_memcached}" = "true" ]; then \
      echo "extension=memcached.so" > ${PHP_DIR}/etc/conf.d/20-memcached.ini; \
    fi; \
    if [ "${USE_imagick}" = "true" ]; then \
      echo "extension=imagick.so" > ${PHP_DIR}/etc/conf.d/20-imagick.ini; \
    fi; \
    if [ "${USE_mongodb}" = "true" ]; then \
      echo "extension=mongodb.so" > ${PHP_DIR}/etc/conf.d/20-mongodb.ini; \
    fi; \
    if [ "${USE_swoole}" = "true" ]; then \
      echo "extension=swoole.so" > ${PHP_DIR}/etc/conf.d/20-swoole.ini; \
    fi; \
    if [ "${USE_snuffleupagus}" = "true" ]; then \
      echo "extension=snuffleupagus.so" > ${PHP_DIR}/etc/conf.d/30-snuffleupagus.ini; \
      echo "sp.configuration_file=${PHP_DIR}/etc/snuffleupagus.rules" >> ${PHP_DIR}/etc/conf.d/30-snuffleupagus.ini; \
    fi

# 复制 Snuffleupagus 安全规则配置（条件性使用）
COPY conf/snuffleupagus.rules ${PHP_DIR}/etc/snuffleupagus.rules

# 创建默认 PHP 测试页面
RUN echo '<?php phpinfo(); ?>' > /www/wwwroot/html/phpinfo.php

# ============================================================
# 文件权限设置（CIS Docker Benchmark 合规）
# ============================================================
RUN touch ${PHP_DIR}/var/log/php-fpm.log \
    && touch ${PHP_DIR}/var/run/php-fpm.pid \
    # 配置文件权限
    && find ${PHP_DIR}/etc -type d -exec chmod 700 {} \; \
    && find ${PHP_DIR}/etc -type f -exec chmod 600 {} \; \
    # 日志目录权限
    && chmod 750 ${PHP_DIR}/var/log \
    && chmod 640 ${PHP_DIR}/var/log/php-fpm.log \
    # PID 文件权限
    && chmod 750 ${PHP_DIR}/var/run \
    # 网站目录权限
    && chown -R www-data:www-data /www/wwwroot/html \
    && chmod 755 /www/wwwroot/html \
    # 临时目录权限
    && chown -R www-data:www-data /tmp/php-session \
    && chown -R www-data:www-data /tmp/php-upload \
    && chmod 700 /tmp/php-session \
    && chmod 700 /tmp/php-upload \
    # PHP 目录属主
    && chown -R root:root ${PHP_DIR}

# CIS Docker 4.9 - 使用 COPY 而非 ADD
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 500 /docker-entrypoint.sh

# CIS Docker 4.6 - 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD php-fpm-healthcheck || exit 1

EXPOSE 36000

# 优雅停止信号
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/docker-entrypoint.sh"]

# 前台运行 PHP-FPM（Docker 要求主进程在前台运行）
CMD ["/opt/php/sbin/php-fpm", "--nodaemonize"]
