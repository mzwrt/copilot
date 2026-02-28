# =======================================================
# PostgreSQL Docker 构建文件
# 基于源码编译 PostgreSQL，安全加固配置
# 符合 CIS Docker Benchmark 和 PCI DSS 安全基准
# =======================================================
#
# 构建示例:
#   docker build -t postgresql .
#   docker build --build-arg PG_VERSION=17.4 -t postgresql .
#
# 运行示例:
#   docker run -d --name postgresql postgresql
#   docker compose up -d
#

###############################################
# 版本配置 (Version Configuration)
# 构建时可通过 --build-arg 覆盖
###############################################

# PostgreSQL 版本（必须手动指定）
ARG PG_VERSION=17.4

# =======================================================
# Stage 1: 编译阶段 (Build Stage)
# 使用完整 Debian 进行编译，最终镜像只保留运行时文件
# =======================================================
FROM debian:bookworm-slim AS builder

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明所有 ARGs（FROM 之后 ARG 需要重新声明）
ARG PG_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PG_DIR=/opt/postgresql \
    PG_SRC_DIR=/opt/postgresql/src

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    wget \
    ca-certificates \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libxml2-dev \
    libxslt1-dev \
    libldap2-dev \
    libpam0g-dev \
    uuid-dev \
    libsystemd-dev \
    libicu-dev \
    liblz4-dev \
    libzstd-dev \
    bison \
    flex \
    && rm -rf /var/lib/apt/lists/*

# 创建构建目录
RUN mkdir -p ${PG_SRC_DIR} \
    && chmod 750 ${PG_SRC_DIR} \
    && chown root:root ${PG_SRC_DIR}

# 下载 PostgreSQL 源码
RUN cd ${PG_SRC_DIR} \
    && wget --tries=5 --waitretry=2 --no-check-certificate \
       "https://ftp.postgresql.org/pub/source/v${PG_VERSION}/postgresql-${PG_VERSION}.tar.bz2" \
    && tar -jxf "postgresql-${PG_VERSION}.tar.bz2" \
    && mv "postgresql-${PG_VERSION}" postgresql \
    && rm -f "postgresql-${PG_VERSION}.tar.bz2" \
    && chown -R root:root ${PG_SRC_DIR}/postgresql

# 编译安装 PostgreSQL（启用安全和性能相关选项）
RUN set -eux; \
    cd ${PG_SRC_DIR}/postgresql; \
    ./configure \
        --prefix=${PG_DIR} \
        --with-openssl \
        --with-pam \
        --with-ldap \
        --with-libxml \
        --with-libxslt \
        --with-uuid=e2fs \
        --with-systemd \
        --with-icu \
        --with-lz4 \
        --with-zstd \
        --with-readline \
        --with-system-tzdata=/usr/share/zoneinfo \
    ; \
    make -j$(nproc) world-bin; \
    make install-world-bin

# =======================================================
# Stage 2: 运行阶段 (Runtime Stage)
# CIS Docker Benchmark 合规 - 最小化镜像
# =======================================================
FROM debian:bookworm-slim

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# OCI 镜像标签（用于 Docker Hub 展示）
LABEL org.opencontainers.image.title="PostgreSQL" \
      org.opencontainers.image.description="Security-hardened PostgreSQL compiled from source, CIS Docker Benchmark and PCI DSS compliant" \
      org.opencontainers.image.source="https://github.com/mzwrt/copilot" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    PG_DIR=/opt/postgresql \
    PGDATA=/opt/postgresql/data \
    PATH="/opt/postgresql/bin:${PATH}"

# CIS Docker 4.1 - 创建非 root 运行用户
RUN groupadd -r -g 999 postgres \
    && useradd -r -u 999 -g postgres -s /sbin/nologin -d /opt/postgresql postgres

# CIS Docker 4.3 - 仅安装必要的运行时依赖（最小化）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    libreadline8 \
    zlib1g \
    libxml2 \
    libxslt1.1 \
    libldap-2.5-0 \
    libpam0g \
    libuuid1 \
    libsystemd0 \
    libicu72 \
    liblz4-1 \
    libzstd1 \
    locales \
    gosu \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean \
    && gosu nobody true

# 生成 UTF-8 locale（PostgreSQL 需要）
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
    && locale-gen

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    LD_LIBRARY_PATH=/opt/postgresql/lib

# CIS Docker 4.8 - 移除不必要的 setuid/setgid 权限
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# 从编译阶段复制 PostgreSQL 安装文件
COPY --from=builder /opt/postgresql/bin /opt/postgresql/bin
COPY --from=builder /opt/postgresql/lib /opt/postgresql/lib
COPY --from=builder /opt/postgresql/share /opt/postgresql/share

# 创建目录结构
RUN mkdir -p \
    ${PG_DIR}/etc \
    ${PG_DIR}/var/log \
    ${PG_DIR}/var/run \
    ${PG_DIR}/data \
    ${PG_DIR}/wal

# ============================================================
# 复制本地配置文件
# ============================================================

# 复制 PostgreSQL 配置文件
COPY conf/postgresql.conf ${PG_DIR}/etc/postgresql.conf
COPY conf/pg_hba.conf ${PG_DIR}/etc/pg_hba.conf

# ============================================================
# 文件权限设置（CIS Docker Benchmark 合规）
# ============================================================
RUN touch ${PG_DIR}/var/log/postgresql.log \
    # 配置文件权限
    && find ${PG_DIR}/etc -type d -exec chmod 700 {} \; \
    && find ${PG_DIR}/etc -type f -exec chmod 600 {} \; \
    # 日志目录权限
    && chmod 750 ${PG_DIR}/var/log \
    && chmod 640 ${PG_DIR}/var/log/postgresql.log \
    # PID/Socket 文件权限
    && chmod 750 ${PG_DIR}/var/run \
    # 数据目录权限（PostgreSQL 要求 700）
    && chmod 700 ${PG_DIR}/data \
    # WAL 目录权限
    && chmod 700 ${PG_DIR}/wal \
    # PostgreSQL 目录属主
    && chown -R root:root ${PG_DIR} \
    && chown -R postgres:postgres ${PG_DIR}/var/log \
    && chown -R postgres:postgres ${PG_DIR}/var/run \
    && chown -R postgres:postgres ${PG_DIR}/data \
    && chown -R postgres:postgres ${PG_DIR}/wal \
    && chown postgres:postgres ${PG_DIR}/etc/postgresql.conf \
    && chown postgres:postgres ${PG_DIR}/etc/pg_hba.conf

# CIS Docker 4.9 - 使用 COPY 而非 ADD
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 500 /docker-entrypoint.sh

# CIS Docker 4.6 - 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=30s \
    CMD pg-healthcheck || exit 1

EXPOSE 55432

# 优雅停止信号
STOPSIGNAL SIGTERM

ENTRYPOINT ["/docker-entrypoint.sh"]

# 前台运行 PostgreSQL（Docker 要求主进程在前台运行）
CMD ["postgres", "-c", "config_file=/opt/postgresql/etc/postgresql.conf"]
