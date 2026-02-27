# =======================================================
# Nginx Docker 构建文件
# 基于 nginx-install.sh 编写
# 符合 CIS Docker Benchmark 和 CIS Nginx Benchmark
# 高安全、高性能配置
# =======================================================
#
# 构建示例:
#   docker build -t nginx-custom .
#   docker build --build-arg USE_modsecurity=false -t nginx-custom .
#   docker build --build-arg NGINX_FAKE_NAME="MyServer" -t nginx-custom .
#
# 运行示例:
#   docker run -d -p 80:80 -p 443:443 --name nginx nginx-custom
#   docker compose up -d
#

###############################################
# 第三方插件开关 (Third-party Plugin Toggles)
# 设置为 "true" 启用，"false" 禁用
# 构建时可通过 --build-arg 覆盖
###############################################

# ngx-fancyindex 美化目录浏览模块
# 设置为 "true" 即启用
ARG USE_ngx_fancyindex=false

# PCRE2 正则表达式模块
# 设置为 "false" 即不启用
ARG USE_PCRE2=true

# ngx_cache_purge 缓存清除模块
# 设置为 "false" 即不启用
ARG USE_ngx_cache_purge=true

# ngx_http_headers_more_filter_module 自定义响应头模块
# 设置为 "false" 即不启用
ARG USE_ngx_http_headers_more_filter_module=true

# ngx_http_proxy_connect_module 正向代理 CONNECT 模块
# 设置为 "false" 即不启用
ARG USE_ngx_http_proxy_connect_module=true

# ngx_brotli 压缩模块
# 设置为 "false" 即不启用
ARG USE_ngx_brotli=true

# openssl 使用自编译 OpenSSL（高版本/高性能）
# 设置为 "false" 即不启用
ARG USE_openssl=true

# modsecurity Web 应用防火墙引擎
# 设置为 "false" 即不启用
ARG USE_modsecurity=true

# OWASP 核心规则集
# 设置为 "false" 即不启用
ARG USE_owasp=true

# modsecurity-nginx 连接器模块
# 设置为 "false" 即不启用
ARG USE_modsecurity_nginx=true

###############################################
# 版本配置 (Version Configuration)
# 构建时可通过 --build-arg 覆盖
###############################################

# OpenSSL 版本 (手动指定)
ARG OPENSSL_VERSION=3.5.4

# Nginx 版本 (手动指定)
ARG NGINX_VERSION=1.28.0

# ngx-fancyindex 版本
ARG FANCYINDEX_VERSION=0.5.2

###############################################
# Nginx 伪装配置 (Server Identity)
# 隐藏真实 Nginx 版本信息，增强安全性
###############################################

# 自定义服务器名称 (例如: "OWASP WAF")，留空使用默认值
ARG NGINX_FAKE_NAME=""

# 自定义版本号 (例如: "5.1.24")，留空使用默认版本号
ARG NGINX_VERSION_NUMBER=""


# =======================================================
# Stage 1: 编译阶段 (Build Stage)
# 使用完整 Debian 进行编译，最终镜像只保留运行时文件
# =======================================================
FROM debian:bookworm-slim AS builder

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明所有 ARGs（FROM 之后 ARG 需要重新声明）
ARG USE_ngx_fancyindex
ARG USE_PCRE2
ARG USE_ngx_cache_purge
ARG USE_ngx_http_headers_more_filter_module
ARG USE_ngx_http_proxy_connect_module
ARG USE_ngx_brotli
ARG USE_openssl
ARG USE_modsecurity
ARG USE_owasp
ARG USE_modsecurity_nginx
ARG OPENSSL_VERSION
ARG NGINX_VERSION
ARG FANCYINDEX_VERSION
ARG NGINX_FAKE_NAME
ARG NGINX_VERSION_NUMBER

ENV DEBIAN_FRONTEND=noninteractive \
    OPT_DIR=/opt \
    NGINX_DIR=/opt/nginx \
    NGINX_SRC_DIR=/opt/nginx/src

# 安装编译依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-utils \
    build-essential \
    libssl-dev \
    zlib1g-dev \
    libaio-dev \
    libjemalloc-dev \
    libgd-dev \
    libgeoip-dev \
    libxslt1-dev \
    libbrotli-dev \
    libcurl4-openssl-dev \
    libyaml-dev \
    unzip \
    git \
    cmake \
    gcc \
    g++ \
    make \
    wget \
    pkg-config \
    libpcre2-dev \
    libpcre2-8-0 \
    liblua5.3-dev \
    libmaxminddb0 \
    libmaxminddb-dev \
    liblmdb-dev \
    libtool \
    liblzma-dev \
    autoconf \
    automake \
    gawk \
    libyajl-dev \
    libxml2-dev \
    ca-certificates \
    curl \
    patch \
    && rm -rf /var/lib/apt/lists/*

# 创建构建目录
RUN mkdir -p ${NGINX_SRC_DIR} \
    && chmod 750 ${NGINX_SRC_DIR} \
    && chown root:root ${NGINX_SRC_DIR}

# 下载 Nginx 源码
RUN cd ${NGINX_DIR} \
    && wget --tries=5 --waitretry=2 --no-check-certificate \
       "https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz" \
    && tar -zxf "nginx-${NGINX_VERSION}.tar.gz" \
    && mv "nginx-${NGINX_VERSION}" nginx \
    && rm -f "nginx-${NGINX_VERSION}.tar.gz" \
    && chown -R root:root ${NGINX_DIR}/nginx

# 应用 Nginx 伪装名称补丁（隐藏服务器标识，CIS 合规）
RUN set -eux; \
    if [ -n "${NGINX_FAKE_NAME}" ]; then \
      safe_name=$(printf '%s' "${NGINX_FAKE_NAME}" | sed 's/[&/\]/\\&/g'); \
      sed -i "s/static u_char ngx_http_server_string\[\] = \"Server: nginx\" CRLF;/static u_char ngx_http_server_string\[\] = \"Server: ${safe_name}\" CRLF;/g" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_header_filter_module.c; \
      sed -i "s/static u_char ngx_http_server_full_string\[\] = \"Server: \" NGINX_VER CRLF;/static u_char ngx_http_server_full_string\[\] = \"Server: ${safe_name}\" CRLF;/g" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_header_filter_module.c; \
      sed -i "s/static u_char ngx_http_server_build_string\[\] = \"Server: \" NGINX_VER_BUILD CRLF;/static u_char ngx_http_server_build_string\[\] = \"Server: ${safe_name}\" CRLF;/g" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_header_filter_module.c; \
      sed -i "s/<hr><center>\" NGINX_VER_BUILD \"<\/center>\" CRLF/<hr><center>${safe_name}<\/center>\" CRLF/" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_special_response.c; \
      sed -i "s/<hr><center>nginx<\/center>\" CRLF/<hr><center>${safe_name}<\/center>\" CRLF/" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_special_response.c; \
      sed -i "s/<hr><center>\" NGINX_VER \"<\/center>\" CRLF/<hr><center>${safe_name}<\/center>\" CRLF/" \
        ${NGINX_DIR}/nginx/src/http/ngx_http_special_response.c; \
    fi

# 下载 PCRE2 模块
RUN set -eux; \
    if [ "${USE_PCRE2}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      pcre2_version=$(curl -sSL --retry 5 --retry-delay 2 --retry-connrefused \
        "https://api.github.com/repos/PhilipHazel/pcre2/releases/latest" \
        | grep -oP '"tag_name":\s*"\K[^"]+') || true; \
      if [ -z "$pcre2_version" ]; then pcre2_version="pcre2-10.45"; fi; \
      wget --tries=5 --waitretry=2 --no-check-certificate \
        "https://github.com/PhilipHazel/pcre2/releases/download/$pcre2_version/$pcre2_version.tar.gz"; \
      tar -zxf "$pcre2_version.tar.gz"; \
      mv "$pcre2_version" pcre2; \
      rm -f "$pcre2_version.tar.gz"; \
    fi

# 下载 OpenSSL
RUN set -eux; \
    if [ "${USE_openssl}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      wget --tries=5 --waitretry=2 --no-check-certificate \
        "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"; \
      tar -zxf "openssl-${OPENSSL_VERSION}.tar.gz"; \
      mv "openssl-${OPENSSL_VERSION}" openssl; \
      rm -f "openssl-${OPENSSL_VERSION}.tar.gz"; \
    fi

# 下载 ngx_brotli 压缩模块
RUN set -eux; \
    if [ "${USE_ngx_brotli}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      git clone --recursive --depth 1 https://github.com/google/ngx_brotli.git; \
      cd ngx_brotli; \
      git submodule update --init; \
    fi

# 下载 ngx_cache_purge 缓存清除模块
RUN set -eux; \
    if [ "${USE_ngx_cache_purge}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      ngx_cache_purge_version=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
        "https://api.github.com/repos/FRiCKLE/ngx_cache_purge/tags" \
        | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4) || true; \
      if [ -z "$ngx_cache_purge_version" ]; then ngx_cache_purge_version="2.3"; fi; \
      wget --tries=5 --waitretry=2 --no-check-certificate \
        "https://github.com/FRiCKLE/ngx_cache_purge/archive/refs/tags/$ngx_cache_purge_version.zip"; \
      unzip "$ngx_cache_purge_version.zip"; \
      mv "ngx_cache_purge-$ngx_cache_purge_version" ngx_cache_purge; \
      rm -f "$ngx_cache_purge_version.zip"; \
    fi

# 下载 ngx_http_headers_more_filter_module 自定义响应头模块
RUN set -eux; \
    if [ "${USE_ngx_http_headers_more_filter_module}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      version=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
        "https://api.github.com/repos/openresty/headers-more-nginx-module/tags" \
        | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4 | sed 's/^v//') || true; \
      if [ -z "$version" ]; then version="0.38"; fi; \
      wget --tries=5 --waitretry=2 --no-check-certificate \
        "https://github.com/openresty/headers-more-nginx-module/archive/refs/tags/v${version}.tar.gz"; \
      tar -xzf "v${version}.tar.gz"; \
      mv "headers-more-nginx-module-${version}" headers-more-nginx-module; \
      rm -f "v${version}.tar.gz"; \
    fi

# 下载 ngx_http_proxy_connect_module 正向代理模块并应用补丁
RUN set -eux; \
    if [ "${USE_ngx_http_proxy_connect_module}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      version=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
        "https://api.github.com/repos/chobits/ngx_http_proxy_connect_module/tags" \
        | grep -o '"name": "[^"]*' | head -n 1 | cut -d '"' -f 4) || true; \
      if [ -z "$version" ]; then echo "错误：无法获取 ngx_http_proxy_connect_module 版本"; exit 1; fi; \
      wget --tries=5 --waitretry=2 --no-check-certificate \
        "https://github.com/chobits/ngx_http_proxy_connect_module/archive/refs/tags/$version.zip"; \
      unzip "$version.zip"; \
      rm -f "$version.zip"; \
      mv "ngx_http_proxy_connect_module-${version#v}" ngx_http_proxy_connect_module; \
      cd ${NGINX_DIR}/nginx; \
      cp ${NGINX_SRC_DIR}/ngx_http_proxy_connect_module/patch/proxy_connect_rewrite_102101.patch .; \
      patch -p1 -f < proxy_connect_rewrite_102101.patch; \
      rm -f proxy_connect_rewrite_102101.patch; \
    fi

# 下载 ngx_fancyindex 美化目录浏览模块
RUN set -eux; \
    if [ "${USE_ngx_fancyindex}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      wget --tries=5 --waitretry=2 --no-check-certificate \
        "https://github.com/aperezdc/ngx-fancyindex/releases/download/v${FANCYINDEX_VERSION}/ngx-fancyindex-${FANCYINDEX_VERSION}.tar.xz"; \
      tar -xJf "ngx-fancyindex-${FANCYINDEX_VERSION}.tar.xz"; \
      mv "ngx-fancyindex-${FANCYINDEX_VERSION}" ngx_fancyindex; \
      rm -f "ngx-fancyindex-${FANCYINDEX_VERSION}.tar.xz"; \
    fi

# 编译安装 ModSecurity WAF 引擎
RUN set -eux; \
    if [ "${USE_modsecurity}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      git clone --depth 1 -b v3/master --single-branch \
        https://github.com/SpiderLabs/ModSecurity ModSecurity; \
      cd ModSecurity; \
      git submodule update --recursive; \
      git submodule init; \
      git submodule update; \
      ./build.sh; \
      ./configure --with-pcre2; \
      make -j$(nproc) || make; \
      make install; \
    fi

# 下载 ModSecurity-nginx 连接器
RUN set -eux; \
    if [ "${USE_modsecurity_nginx}" = "true" ]; then \
      cd ${NGINX_SRC_DIR}; \
      git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx.git; \
      chown -R root:root ${NGINX_SRC_DIR}/ModSecurity-nginx; \
    fi

# 确保 ModSecurity 目录存在（即使未编译，COPY 不会失败）
RUN mkdir -p /usr/local/modsecurity/lib

# 配置、编译、安装 Nginx
# 注意：Docker 镜像中去除 -march=native -mtune=native 以保证镜像可移植性
# 如需针对特定 CPU 优化，可通过 --build-arg 传入 EXTRA_CC_OPT="-march=native -mtune=native"
ARG EXTRA_CC_OPT=""
RUN set -eux; \
    cd ${NGINX_DIR}/nginx; \
    EXTRA_ARGS=""; \
    [ "${USE_ngx_cache_purge}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/ngx_cache_purge" || true; \
    [ "${USE_ngx_brotli}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/ngx_brotli" || true; \
    [ "${USE_ngx_http_headers_more_filter_module}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/headers-more-nginx-module" || true; \
    [ "${USE_ngx_http_proxy_connect_module}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/ngx_http_proxy_connect_module" || true; \
    [ "${USE_modsecurity_nginx}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/ModSecurity-nginx" || true; \
    [ "${USE_openssl}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --with-openssl=${NGINX_SRC_DIR}/openssl" || true; \
    [ "${USE_PCRE2}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --with-pcre=${NGINX_SRC_DIR}/pcre2" || true; \
    [ "${USE_ngx_fancyindex}" = "true" ] && \
      EXTRA_ARGS="$EXTRA_ARGS --add-module=${NGINX_SRC_DIR}/ngx_fancyindex" || true; \
    ./configure \
      --prefix=${NGINX_DIR} \
      --user=www-data \
      --group=www-data \
      --with-threads \
      --with-file-aio \
      --with-pcre-jit \
      --with-http_ssl_module \
      --with-http_v2_module \
      --with-http_v3_module \
      --with-http_gzip_static_module \
      --with-http_stub_status_module \
      --with-http_realip_module \
      --with-http_auth_request_module \
      --with-http_sub_module \
      --with-http_flv_module \
      --with-http_mp4_module \
      --with-http_addition_module \
      --with-http_image_filter_module \
      --with-http_gunzip_module \
      --with-stream \
      --with-stream_ssl_module \
      --with-stream_ssl_preread_module \
      --with-compat \
      --with-cc-opt="-O3 -pipe -fPIE -fPIC -flto=auto -fstack-protector-strong -Wformat -Werror=format-security -D_FORTIFY_SOURCE=3 ${EXTRA_CC_OPT}" \
      --with-ld-opt='-ljemalloc -flto=auto -fPIE -fPIC -pie -Wl,-z,relro,-z,now -Wl,-O2 -Wl,--as-needed' \
      $EXTRA_ARGS; \
    make -j$(nproc); \
    make install


# =======================================================
# Stage 2: 运行阶段 (Runtime Stage)
# CIS Docker Benchmark 合规 - 最小化镜像
# =======================================================
FROM debian:bookworm-slim

# hadolint ignore=DL4006
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# 重新声明运行时需要的 ARGs
ARG USE_modsecurity
ARG USE_owasp
ARG USE_modsecurity_nginx

ENV DEBIAN_FRONTEND=noninteractive \
    OPT_DIR=/opt \
    NGINX_DIR=/opt/nginx \
    NGINX_SRC_DIR=/opt/nginx/src \
    PATH="/opt/nginx/sbin:${PATH}"

# CIS Docker 4.1 - 创建非 root 运行用户
RUN groupadd -r www-data 2>/dev/null || true \
    && useradd -r -g www-data -s /sbin/nologin -d /nonexistent www-data 2>/dev/null || true

# CIS Docker 4.3 - 仅安装必要的运行时依赖（最小化）
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libjemalloc2 \
    libgd3 \
    libgeoip1 \
    libxslt1.1 \
    libbrotli1 \
    libpcre2-8-0 \
    libmaxminddb0 \
    liblmdb0 \
    libyajl2 \
    libxml2 \
    libcurl4 \
    liblua5.3-0 \
    zlib1g \
    openssl \
    wget \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# CIS Docker 4.8 - 移除不必要的 setuid/setgid 权限
RUN find / -perm /6000 -type f -exec chmod a-s {} \; 2>/dev/null || true

# 从编译阶段复制 Nginx 二进制文件和默认页面
COPY --from=builder /opt/nginx/sbin /opt/nginx/sbin
COPY --from=builder /opt/nginx/html /opt/nginx/html

# 从编译阶段复制 ModSecurity 库文件
COPY --from=builder /usr/local/modsecurity /usr/local/modsecurity

# 配置 ModSecurity 动态链接库路径
RUN echo "/usr/local/modsecurity/lib" > /etc/ld.so.conf.d/modsecurity.conf \
    && ldconfig

# 创建目录结构（CIS Nginx 合规）
RUN mkdir -p \
    ${NGINX_DIR}/conf \
    ${NGINX_DIR}/conf.d/sites-available \
    ${NGINX_DIR}/conf.d/sites-enabled \
    ${NGINX_DIR}/ssl/default \
    ${NGINX_DIR}/logs \
    ${NGINX_DIR}/modules \
    ${NGINX_DIR}/src/ModSecurity \
    /www/wwwroot/html \
    /opt/owasp/conf \
    /opt/owasp/owasp-rules/plugins \
    /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp

# 根据 CIS Nginx 2.4.2 - 创建默认自签名 SSL 证书
RUN openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
      -keyout ${NGINX_DIR}/ssl/default/default.key \
      -out ${NGINX_DIR}/ssl/default/default.pem \
      -subj "/C=XX/ST=Default/L=Default/O=Default/CN=localhost" \
    && chmod 400 ${NGINX_DIR}/ssl/default/default.key \
    && chmod 600 ${NGINX_DIR}/ssl/default/default.pem

# 下载 Nginx 配置文件
RUN wget -q --tries=5 --waitretry=2 --no-check-certificate \
      -O ${NGINX_DIR}/conf/nginx.conf \
      "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/nginx.conf" \
    && sed -i "s|%NGINX_DIR%|${NGINX_DIR}|g" ${NGINX_DIR}/conf/nginx.conf \
    # 确保 Docker 环境下 daemon off 不冲突
    && sed -i '/^\s*daemon\b/d' ${NGINX_DIR}/conf/nginx.conf

# 下载代理优化配置文件
RUN wget -q --tries=5 --waitretry=2 --no-check-certificate \
      -O ${NGINX_DIR}/conf/proxy.conf \
      "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/proxy.conf" \
    && sed -i "s|%NGINX_DIR%|${NGINX_DIR}|g" ${NGINX_DIR}/conf/proxy.conf

# 下载 PHP 配置文件（为后期开启 PHP 作准备）
RUN wget -q --tries=5 --waitretry=2 --no-check-certificate \
      -O ${NGINX_DIR}/conf/pathinfo.conf \
      "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/php/pathinfo.conf" \
    && wget -q --tries=5 --waitretry=2 --no-check-certificate \
      -O ${NGINX_DIR}/conf/enable-php-84.conf \
      "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/php/enable-php-84.conf"

# 下载 Nginx mime.types 配置（如果远程 nginx.conf 需要）
RUN if [ ! -f ${NGINX_DIR}/conf/mime.types ]; then \
      cp /opt/nginx/html/../conf/mime.types ${NGINX_DIR}/conf/mime.types 2>/dev/null || \
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O ${NGINX_DIR}/conf/mime.types \
        "https://raw.githubusercontent.com/nginx/nginx/master/conf/mime.types" || true; \
    fi

# 下载 ModSecurity 配置文件（条件执行）
RUN set -eux; \
    if [ "${USE_modsecurity}" = "true" ]; then \
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O ${NGINX_SRC_DIR}/ModSecurity/modsecurity.conf \
        "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/ModSecurity/modsecurity.conf"; \
      chown root:root ${NGINX_SRC_DIR}/ModSecurity/modsecurity.conf; \
      chmod 600 ${NGINX_SRC_DIR}/ModSecurity/modsecurity.conf; \
    fi

# 下载 OWASP 核心规则集及相关配置（条件执行）
RUN set -eux; \
    if [ "${USE_owasp}" = "true" ]; then \
      cd /opt/owasp; \
      owasp_VERSION=$(curl -s --retry 5 --retry-delay 2 --retry-connrefused \
        "https://api.github.com/repos/coreruleset/coreruleset/releases/latest" \
        | grep -Po '"tag_name": "\K.*?(?=")') || true; \
      if [ -z "$owasp_VERSION" ]; then owasp_VERSION="v4.8.0"; fi; \
      owasp_VERSION_NO_V=$(echo "$owasp_VERSION" | sed 's/v//g'); \
      owasp_DOWNLOAD_URL="https://github.com/coreruleset/coreruleset/archive/refs/tags/$owasp_VERSION.tar.gz"; \
      curl -L --retry 5 --retry-delay 2 --retry-connrefused \
        -o "coreruleset-$owasp_VERSION.tar.gz" "$owasp_DOWNLOAD_URL"; \
      tar -zxf "coreruleset-$owasp_VERSION.tar.gz"; \
      mv "coreruleset-$owasp_VERSION_NO_V" /opt/owasp/owasp-rules; \
      rm -f "coreruleset-$owasp_VERSION.tar.gz"; \
      # 下载 crs-setup.conf
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/owasp-rules/crs-setup.conf \
        "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/crs-setup.conf"; \
      # 创建 plugins 目录
      mkdir -p /opt/owasp/owasp-rules/plugins; \
      # 下载 WordPress 规则排除插件
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf \
        "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-before.conf" || true; \
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf \
        "https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-config.conf" || true; \
      # 重命名排除规则样例文件
      if [ -f /opt/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example ]; then \
        mv /opt/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf.example \
           /opt/owasp/owasp-rules/rules/REQUEST-900-EXCLUSION-RULES-BEFORE-CRS.conf; \
      fi; \
      if [ -f /opt/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example ]; then \
        mv /opt/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf.example \
           /opt/owasp/owasp-rules/rules/RESPONSE-999-EXCLUSION-RULES-AFTER-CRS.conf; \
      fi; \
      # 下载 OWASP 附加配置文件
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/conf/hosts.deny \
        "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/hosts.deny"; \
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/conf/hosts.allow \
        "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/hosts.allow"; \
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/conf/main.conf \
        "https://raw.githubusercontent.com/mzwrt/system_script/main/nginx/ModSecurity/main.conf"; \
      # 下载 WordPress Nginx 拒绝规则
      wget -q --tries=5 --waitretry=2 --no-check-certificate \
        -O /opt/owasp/conf/nginx-wordpress.conf \
        "https://gist.githubusercontent.com/nfsarmento/57db5abba08b315b67f174cd178bea88/raw/b0768871c3349fdaf549a24268cb01b2be145a6a/nginx-wordpress.conf" || true; \
    fi

# 下载默认首页
RUN wget -q --tries=5 --waitretry=2 --no-check-certificate \
      -O /www/wwwroot/html/index.html \
      "https://raw.githubusercontent.com/mzwrt/system_script/refs/heads/main/nginx/index.html" \
    || echo '<html><body><h1>Welcome</h1></body></html>' > /www/wwwroot/html/index.html

# 创建 PID 文件
RUN touch ${NGINX_DIR}/logs/nginx.pid

# ============================================================
# 文件权限设置（CIS Nginx Benchmark 合规）
# ============================================================

# CIS Nginx - 配置文件权限
RUN find ${NGINX_DIR}/conf -type d -exec chmod 700 {} \; \
    && find ${NGINX_DIR}/conf -type f -exec chmod 600 {} \; \
    && find ${NGINX_DIR}/conf.d -type d -exec chmod 700 {} \; \
    && find ${NGINX_DIR}/conf.d -type f -exec chmod 600 {} \;

# CIS Nginx - SSL 证书权限
RUN chmod 700 ${NGINX_DIR}/ssl \
    && chmod 700 ${NGINX_DIR}/ssl/default

# CIS Nginx - 日志目录权限
RUN chmod 750 ${NGINX_DIR}/logs \
    && chmod u-x,go-wx ${NGINX_DIR}/logs/nginx.pid

# CIS Nginx - 模块目录权限
RUN [ -d "${NGINX_DIR}/modules" ] && chmod 750 ${NGINX_DIR}/modules || true

# OWASP 规则文件权限
RUN find /opt/owasp -type d -exec chmod 700 {} \; 2>/dev/null || true \
    && find /opt/owasp -type f -name "*.conf" -exec chmod 600 {} \; -exec chown root:root {} \; 2>/dev/null || true \
    && chown -R root:root /opt/owasp 2>/dev/null || true

# CIS Nginx 2.5.2 - 默认网站目录权限
RUN chown -R www-data:www-data /www/wwwroot/html \
    && chmod 755 /www/wwwroot/html \
    && find /www/wwwroot/html -type f -exec chmod 444 {} \;

# Nginx 目录属主
RUN chown -R root:root ${NGINX_DIR}

# Nginx 缓存目录权限
RUN chown -R www-data:www-data /var/cache/nginx

# CIS Docker 4.9 - 使用 COPY 而非 ADD
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod 500 /docker-entrypoint.sh

# CIS Docker 4.6 - 健康检查
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
    CMD curl -sf http://127.0.0.1/ || exit 1

EXPOSE 80 443

# 优雅停止信号
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/docker-entrypoint.sh"]

# 前台运行 Nginx（Docker 要求主进程在前台运行）
CMD ["/opt/nginx/sbin/nginx", "-g", "daemon off;"]
