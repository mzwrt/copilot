#!/bin/sh
# =======================================================
# Redis Docker 入口脚本
# 负责运行时初始化和权限检查
# =======================================================

set -e

REDIS_DIR="/opt/redis"

# 确保目录存在且可写
mkdir -p ${REDIS_DIR}/var/log 2>/dev/null || true
mkdir -p ${REDIS_DIR}/var/run 2>/dev/null || true
mkdir -p ${REDIS_DIR}/data 2>/dev/null || true
touch ${REDIS_DIR}/var/log/redis.log 2>/dev/null || true

# Set Redis password from environment variable
if [ -n "${REDIS_PASSWORD}" ]; then
    # Remove any existing requirepass directive to prevent duplicates on restart
    sed -i '/^requirepass /d' ${REDIS_DIR}/etc/redis.conf
    # Use printf to write password directly to a temp file, avoiding sed metacharacter issues
    printf 'requirepass %s\n' "${REDIS_PASSWORD}" > /tmp/redis_auth.conf
    # Append to the config after the comment marker
    sed -i '/^# requirepass/r /tmp/redis_auth.conf' ${REDIS_DIR}/etc/redis.conf
    rm -f /tmp/redis_auth.conf
    echo "Redis password configured from environment variable"
fi

# 创建健康检查脚本（检查 Redis 进程是否正常响应）
if [ ! -f /usr/local/bin/redis-healthcheck ]; then
    cat > /usr/local/bin/redis-healthcheck << 'HEALTHEOF'
#!/bin/sh
REDIS_DIR="/opt/redis"
if [ -n "${REDIS_PASSWORD}" ]; then
    ${REDIS_DIR}/bin/redis-cli -p 36379 -a "${REDIS_PASSWORD}" --no-auth-warning ping | grep -q PONG
else
    ${REDIS_DIR}/bin/redis-cli -p 36379 ping | grep -q PONG
fi
HEALTHEOF
    chmod 555 /usr/local/bin/redis-healthcheck
fi

# 执行主命令
exec "$@"
