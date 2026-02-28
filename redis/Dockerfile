# =======================================================
# Redis Docker 构建文件
# 基于源码编译 Redis，安全加固配置
# 符合 CIS Docker Benchmark 安全基准
# =======================================================
#
# 构建示例:
#   docker build -t redis .
#   docker build --build-arg REDIS_VERSION=7.4.4 -t redis .
#
# 运行示例:
#   docker run -d --name redis redis
#   docker compose up -d
#

###############################################
# 版本配置 (Version Configuration)
# 构建时可通过 --build-arg 覆盖
###############################################

# Redis 版本（必须手动指定）
ARG REDIS_VERSION=7.4.4

# =======================================================
# Stage 1: 编译阶段 (Build Stage)
# 使用完整 Debian 进行编译，最终镜像只保留运行时文件
# =======================================================
FROM debian:bookworm-slim AS builder

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明所有 ARGs（FROM 之后 ARG 需要重新声明）
ARG REDIS_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    REDIS_DIR=/opt/redis \
    REDIS_SRC_DIR=/opt/redis/src

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    wget \
    ca-certificates \
    libssl-dev \
    libsystemd-dev \
    && rm -rf /var/lib/apt/lists/*

# 创建构建目录
RUN mkdir -p ${REDIS_SRC_DIR} \
    && chmod 750 ${REDIS_SRC_DIR} \
    && chown root:root ${REDIS_SRC_DIR}

# 下载 Redis 源码
RUN cd ${REDIS_SRC_DIR} \
    && wget --tries=5 --waitretry=2 --no-check-certificate \
       "https://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz" \
    && tar -zxf "redis-${REDIS_VERSION}.tar.gz" \
    && mv "redis-${REDIS_VERSION}" redis \
    && rm -f "redis-${REDIS_VERSION}.tar.gz" \
    && chown -R root:root ${REDIS_SRC_DIR}/redis

# 编译安装 Redis
RUN set -eux; \
    cd ${REDIS_SRC_DIR}/redis; \
    make -j$(nproc) BUILD_TLS=yes USE_SYSTEMD=yes; \
    make PREFIX=${REDIS_DIR} install

# =======================================================
# Stage 2: 运行阶段 (Runtime Stage)
# CIS Docker Benchmark 合规 - 最小化镜像
# =======================================================
FROM debian:bookworm-slim

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OCI 镜像标签（用于 Docker Hub 展示）
LABEL org.opencontainers.image.title="Redis" \
      org.opencontainers.image.description="Security-hardened Redis compiled from source, CIS Docker Benchmark compliant" \
      org.opencontainers.image.source="https://github.com/mzwrt/copilot" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    REDIS_DIR=/opt/redis \
    PATH="/opt/redis/bin:${PATH}"

# CIS Docker 4.1 - 创建非 root 运行用户
RUN groupadd -r -g 999 redis \
    && useradd -r -u 999 -g redis -s /sbin/nologin -d /nonexistent redis

# CIS Docker 4.3 - 仅安装必要的运行时依赖（最小化）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libsystemd0 \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# CIS Docker 4.8 - 移除不必要的 setuid/setgid 权限
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# 从编译阶段复制 Redis 安装文件
COPY --from=builder /opt/redis/bin /opt/redis/bin

# 创建目录结构
RUN mkdir -p \
    ${REDIS_DIR}/etc \
    ${REDIS_DIR}/var/log \
    ${REDIS_DIR}/var/run \
    ${REDIS_DIR}/data

# ============================================================
# 复制本地配置文件
# ============================================================

# 复制 Redis 配置文件
COPY conf/redis.conf ${REDIS_DIR}/etc/redis.conf

# ============================================================
# 文件权限设置（CIS Docker Benchmark 合规）
# ============================================================
RUN touch ${REDIS_DIR}/var/log/redis.log \
    && touch ${REDIS_DIR}/var/run/redis.pid \
    # 配置文件权限
    && find ${REDIS_DIR}/etc -type d -exec chmod 700 {} \; \
    && find ${REDIS_DIR}/etc -type f -exec chmod 600 {} \; \
    # 日志目录权限
    && chmod 750 ${REDIS_DIR}/var/log \
    && chmod 640 ${REDIS_DIR}/var/log/redis.log \
    # PID 文件权限
    && chmod 750 ${REDIS_DIR}/var/run \
    # 数据目录权限
    && chmod 750 ${REDIS_DIR}/data \
    # Redis 目录属主
    && chown -R root:root ${REDIS_DIR} \
    && chown -R redis:redis ${REDIS_DIR}/var/log \
    && chown -R redis:redis ${REDIS_DIR}/var/run \
    && chown -R redis:redis ${REDIS_DIR}/data \
    && chown redis:redis ${REDIS_DIR}/etc/redis.conf

# CIS Docker 4.9 - 使用 COPY 而非 ADD
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 500 /docker-entrypoint.sh

# CIS Docker 4.6 - 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD redis-healthcheck || exit 1

EXPOSE 36379

# 优雅停止信号
STOPSIGNAL SIGTERM

ENTRYPOINT ["/docker-entrypoint.sh"]

# 前台运行 Redis（Docker 要求主进程在前台运行）
CMD ["/opt/redis/bin/redis-server", "/opt/redis/etc/redis.conf"]
