#!/bin/sh
# =======================================================
# PHP-FPM Docker 入口脚本
# 负责运行时初始化和权限检查
# =======================================================

set -e

PHP_DIR="/opt/php"

# 确保日志目录存在且可写
mkdir -p ${PHP_DIR}/var/log 2>/dev/null || true
mkdir -p ${PHP_DIR}/var/run 2>/dev/null || true
touch ${PHP_DIR}/var/log/php-fpm.log 2>/dev/null || true
touch ${PHP_DIR}/var/run/php-fpm.pid 2>/dev/null || true

# 确保临时目录存在且权限正确
for dir in php-session php-upload; do
    mkdir -p /tmp/${dir} 2>/dev/null || true
    chown www-data:www-data /tmp/${dir} 2>/dev/null || true
    chmod 700 /tmp/${dir} 2>/dev/null || true
done

# 确保网站目录存在
mkdir -p /www/wwwroot/html 2>/dev/null || true

# PHP-FPM 配置测试
if [ "$1" = "/opt/php/sbin/php-fpm" ] || [ "$1" = "php-fpm" ]; then
    echo "正在验证 PHP-FPM 配置..."
    if ! /opt/php/sbin/php-fpm -t 2>&1; then
        echo "错误: PHP-FPM 配置验证未通过，请检查配置文件" >&2
        exit 1
    fi
fi

# 执行主命令
exec "$@"
