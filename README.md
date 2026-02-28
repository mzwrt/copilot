# Nginx + PHP-FPM Docker 安全部署方案

基于 CIS Docker Benchmark、CIS Nginx Benchmark 和 PCI DSS v4.0 标准的 Nginx + PHP-FPM 安全容器化部署方案。

## 两种部署方式

### 方式一：使用 GHCR 预构建镜像（推荐）

镜像由 GitHub Actions 自动构建并发布到 GitHub Container Registry，无需本地编译。

```bash
cd nginx

# 拉取预构建镜像并启动（先修改 docker-compose.ghcr.yml 中的镜像地址）
docker compose -f docker-compose.ghcr.yml up -d
```

### 方式二：本地构建

在本地从源码编译 Nginx 及所有模块。

```bash
cd nginx

# 构建镜像（约 15-30 分钟）
docker compose build

# 启动容器
docker compose up -d
```

> 📖 详细教程请参阅 [`nginx/README.md`](nginx/README.md)

### 验证部署

```bash
cd nginx

# 运行安全检查
bash security/cis-docker-benchmark/docker-bench-check.sh

# 运行验证测试
bash tests/validate.sh
```

---

## Nginx + PHP-FPM 联合部署教程

本章节详细说明如何将 Nginx 和 PHP-FPM 两个容器配合使用，实现完整的 PHP Web 应用部署方案，同时满足 CIS Docker Benchmark 和 PCI DSS v4.0 安全合规要求。

### 架构概览

```
                  ┌─── Docker Network: nginx-network ───┐
                  │                                     │
  客户端请求 ───▶ │  ┌─────────┐   TCP:9000  ┌───────┐ │
  HTTP/HTTPS      │  │  Nginx  │ ──────────▶ │  PHP  │ │
  :80 / :443      │  │ 容器    │             │ -FPM  │ │
                  │  └─────────┘             └───────┘ │
                  │       │                      │     │
                  │       ▼                      ▼     │
                  │  ┌──────────────────────────────┐  │
                  │  │   共享卷: wwwroot            │  │
                  │  │   /www/wwwroot               │  │
                  │  └──────────────────────────────┘  │
                  └─────────────────────────────────────┘
```

**工作原理**：
1. 客户端发送 HTTP/HTTPS 请求到 Nginx（端口 80/443）
2. Nginx 处理静态文件（HTML、CSS、JS、图片等）直接返回
3. 当请求 `.php` 文件时，Nginx 通过 FastCGI 协议将请求转发到 PHP-FPM（TCP 9000 端口）
4. PHP-FPM 执行 PHP 脚本，将结果返回给 Nginx
5. Nginx 将响应返回给客户端

**关键集成点**：
- **网络通信**：两个容器通过 Docker 网络 `nginx-network` 使用 TCP 9000 端口通信
- **文件共享**：两个容器共享 `wwwroot` 卷（挂载到 `/www/wwwroot`），PHP 文件需要同时被 Nginx 和 PHP-FPM 访问

### 步骤 1：分别构建 Nginx 和 PHP-FPM 镜像

```bash
# 构建 Nginx 镜像
cd nginx
docker compose build
cd ..

# 构建 PHP-FPM 镜像
cd php
docker compose build
cd ..
```

或使用预构建镜像：
```bash
# 修改各自 docker-compose.ghcr.yml 中的 image 地址后拉取
cd nginx && docker compose -f docker-compose.ghcr.yml pull && cd ..
cd php && docker compose -f docker-compose.ghcr.yml pull && cd ..
```

### 步骤 2：启动容器

Nginx 和 PHP-FPM 使用同名外部网络 `nginx-network` 和共享卷 `wwwroot`。按以下顺序启动：

```bash
# 先启动 PHP-FPM（Nginx 依赖 PHP-FPM 的 DNS 解析）
cd php
docker compose up -d
cd ..

# 再启动 Nginx
cd nginx
docker compose up -d
cd ..
```

> **重要说明**：两个 docker-compose 文件都定义了同名的网络 `nginx-network` 和卷 `wwwroot`。Docker 会自动复用已存在的同名网络和卷，因此两个容器会自动加入同一网络并共享同一卷。

### 步骤 3：验证集成

```bash
# 1. 检查两个容器是否在同一网络
docker network inspect nginx-network

# 2. 检查 PHP-FPM 是否正常监听
docker exec php ss -tlnp | grep 9000

# 3. 检查 Nginx 是否能解析 PHP-FPM 容器名
docker exec nginx ping -c 1 php

# 4. 创建测试 PHP 文件
docker exec php sh -c 'echo "<?php phpinfo(); ?>" > /www/wwwroot/html/test.php'

# 5. 验证 PHP 执行（需要先配置站点，见下方）
curl http://localhost/test.php
```

### 步骤 4：配置 Nginx 站点启用 PHP

在 Nginx 容器中创建站点配置文件：

```bash
docker exec -it nginx /bin/bash

# 创建站点配置
cat > /opt/nginx/conf.d/sites-available/php-site.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name example.com www.example.com;

    # CIS 5.2.4 - 限制请求方法（仅允许 GET HEAD POST）
    if ($request_method !~ ^(GET|HEAD|POST)$) {
        return 444;
    }

    # 网站根目录（与 PHP-FPM 容器共享 wwwroot 卷）
    root /www/wwwroot/html;
    index index.php index.html;

    # CIS 5.3.1 - 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "0" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-ancestors 'self'" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;

    # 日志
    access_log /opt/nginx/logs/php-site_access.log;
    error_log /opt/nginx/logs/php-site_error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # 启用 PHP-FPM（通过 Docker 网络 TCP 通信）
    include php/enable-php-84.conf;

    # 禁止访问隐藏文件（CIS 安全合规）
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# 启用站点
ln -sf /opt/nginx/conf.d/sites-available/php-site.conf \
       /opt/nginx/conf.d/sites-enabled/php-site.conf

# 测试配置并重载
/opt/nginx/sbin/nginx -t && /opt/nginx/sbin/nginx -s reload
```

### 步骤 5：HTTPS 安全配置（PCI DSS 4.2.1 合规）

对于生产环境，请将 HTTP 重定向到 HTTPS：

```bash
cat > /opt/nginx/conf.d/sites-available/php-site-ssl.conf << 'EOF'
# HTTP → HTTPS 重定向
server {
    listen 80;
    listen [::]:80;
    server_name example.com www.example.com;
    return 301 https://$host$request_uri;
}

# HTTPS 站点
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name example.com www.example.com;

    # SSL 证书
    ssl_certificate /opt/nginx/ssl/example.com/fullchain.pem;
    ssl_certificate_key /opt/nginx/ssl/example.com/privkey.pem;

    # CIS 4.1.3 / PCI DSS - 仅允许 TLS 1.2 和 TLS 1.3
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;

    # CIS 4.1.13 / PCI DSS 4.2.1 - HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # CIS 5.3.1 - 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "0" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-ancestors 'self'" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;

    # 网站根目录
    root /www/wwwroot/html;
    index index.php index.html;

    # 日志
    access_log /opt/nginx/logs/php-site_access.log;
    error_log /opt/nginx/logs/php-site_error.log;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # 启用 PHP-FPM
    include php/enable-php-84.conf;

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
```

### CIS 和 PCI DSS 安全合规清单

Nginx + PHP-FPM 联合部署在以下安全基准方面已做加固：

#### 容器级安全（CIS Docker Benchmark v1.6.0）

| CIS 编号 | 安全要求 | Nginx | PHP-FPM | 说明 |
|----------|---------|:-----:|:-------:|------|
| 5.3 | cap_drop: ALL | ✅ | ✅ | 丢弃所有 Linux 能力，仅添加必要能力 |
| 5.4 | 非特权模式运行 | ✅ | ✅ | 未使用 --privileged |
| 5.10 | 内存限制 | ✅ 2G | ✅ 2G | 防止内存耗尽攻击 |
| 5.11 | CPU 限制 | ✅ 4.0 | ✅ 4.0 | 防止 CPU 耗尽攻击 |
| 5.12 | 只读根文件系统 | ✅ | ✅ | read_only: true |
| 5.18 | 限制共享内存 | ✅ 256m | ✅ 256m | shm_size 限制 |
| 5.25 | no-new-privileges | ✅ | ✅ | 禁止获取新权限 |
| 5.26 | 健康检查 | ✅ | ✅ | 定期检测服务状态 |
| 5.28 | PID 限制 | ✅ 200 | ✅ 200 | 防止 Fork 炸弹 |

#### 网络安全（CIS Nginx Benchmark v2.0.1 / PCI DSS v4.0）

| 安全项 | 配置 | 说明 |
|--------|------|------|
| TLS 版本 | TLSv1.2 + TLSv1.3 | PCI DSS 4.1 - 禁用 TLS 1.0/1.1 |
| 密码套件 | AEAD 优先 | CIS 4.1.4 - 使用安全密码套件 |
| HSTS | max-age=31536000 | PCI DSS 4.2.1 - 强制 HTTPS |
| 安全响应头 | X-Frame-Options 等 | CIS 5.3.1 - 防止 XSS/点击劫持 |
| 版本隐藏 | server_tokens off | CIS 5.1.2 - 隐藏 Nginx 版本 |
| PHP 版本隐藏 | expose_php = Off | 隐藏 PHP 版本信息 |
| WAF 防护 | ModSecurity + OWASP CRS | 应用层防火墙 |

#### PHP 应用安全

| 安全项 | 配置 | 说明 |
|--------|------|------|
| 危险函数禁用 | disable_functions | 禁用 exec/system/passthru 等 |
| 远程包含 | allow_url_include = Off | 防止远程代码包含 |
| Cookie 安全 | session.cookie_secure = 1 | PCI DSS - 仅 HTTPS 传输 Cookie |
| Cookie HttpOnly | session.cookie_httponly = 1 | 防止 XSS 窃取 Cookie |
| Session 严格模式 | session.use_strict_mode = 1 | 防止 Session 固定攻击 |
| 环境变量清理 | clear_env = yes | PHP-FPM 进程隔离 |

#### 容器间通信安全

| 安全项 | 配置 | 说明 |
|--------|------|------|
| 网络隔离 | 专用 nginx-network | Docker bridge 网络隔离，非 host 模式 |
| 端口限制 | PHP-FPM 不暴露端口 | 仅通过 Docker 内部网络通信（TCP 9000） |
| 共享卷最小化 | 仅共享 wwwroot | PHP 和 Nginx 仅共享网站文件目录 |
| 日志隔离 | 各自独立日志卷 | nginx-logs 和 php-logs 分别挂载 |

### 常见问题

#### Q: Nginx 无法连接 PHP-FPM

**A**: 检查以下几点：

```bash
# 1. 确认两个容器在同一网络
docker network inspect nginx-network | grep -A2 '"Name"'

# 2. 确认 PHP-FPM 容器正在运行且监听 9000 端口
docker exec php ss -tlnp | grep 9000

# 3. 确认 Nginx 能解析 PHP 容器名
docker exec nginx getent hosts php

# 4. 检查 Nginx 错误日志
docker exec nginx tail -20 /opt/nginx/logs/nginx_error.log
```

#### Q: PHP 文件显示源码而不是执行

**A**: 确认站点配置中已包含 PHP 处理：
```nginx
# 在 server {} 块中添加
include php/enable-php-84.conf;
```

#### Q: 文件权限问题（Permission Denied）

**A**: 确保网站文件属于 `www-data` 用户（两个容器都使用 www-data 运行）：
```bash
docker exec php chown -R www-data:www-data /www/wwwroot/html
docker exec php chmod 755 /www/wwwroot/html
```

---

## 安全基准文档

| 安全基准 | 文档路径 | 说明 |
|---------|---------|------|
| CIS Docker Benchmark | [security/cis-docker-benchmark/](nginx/security/cis-docker-benchmark/README.md) | CIS Docker 安全基准 v1.6.0 检查清单 |
| CIS Nginx Benchmark | [security/cis-nginx-benchmark/](nginx/security/cis-nginx-benchmark/README.md) | CIS Nginx 安全基准 v2.0.1 配置 |
| PCI DSS | [security/pci-dss/](nginx/security/pci-dss/README.md) | PCI DSS v4.0 合规配置 |
| Seccomp Profile | [security/seccomp/](nginx/security/seccomp/README.md) | 系统调用白名单限制 |
| AppArmor Profile | [security/apparmor/](nginx/security/apparmor/README.md) | 强制访问控制策略 |
| Secrets 管理 | [security/secrets/](nginx/security/secrets/README.md) | Docker Secrets 密钥管理 |
| 日志与审计 | [security/audit/](nginx/security/audit/README.md) | 审计日志和监控配置 |
| 性能调优 | [security/performance/](nginx/security/performance/README.md) | 进程调优公式和性能优化 |
| 验证与测试 | [tests/](nginx/tests/README.md) | 安全验证和测试脚本 |

## 目录结构

```
.github/
└── workflows/
    ├── docker-build-push.yml          # Nginx GitHub Actions 构建发布工作流
    └── docker-build-push-php.yml      # PHP-FPM GitHub Actions 构建发布工作流

nginx/
├── Dockerfile                         # 多阶段 Docker 构建文件
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - GHCR 镜像拉取用
├── docker-entrypoint.sh               # 容器入口脚本
├── nginx-install.sh                   # 原始裸机安装脚本（参考）
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 Nginx 详细教程
├── DOCKER-USAGE.md                    # 📖 Docker 使用教程
├── conf/                              # Nginx 配置文件
│   ├── nginx.conf                    # 主配置文件
│   ├── proxy.conf                    # 反向代理和缓存配置
│   ├── php/
│   │   ├── enable-php-84.conf        # PHP-FPM FastCGI 配置（TCP:9000）
│   │   └── pathinfo.conf             # PHP Pathinfo 支持
│   └── modsecurity/                  # ModSecurity WAF 配置
├── security/                          # 安全配置
│   ├── seccomp/                       # Seccomp 系统调用限制
│   ├── apparmor/                      # AppArmor 访问控制
│   ├── secrets/                       # Docker Secrets 管理
│   ├── audit/                         # 审计日志配置
│   ├── cis-docker-benchmark/          # CIS Docker 基准检查
│   ├── cis-nginx-benchmark/           # CIS Nginx 基准配置
│   ├── pci-dss/                       # PCI DSS 合规
│   └── performance/                   # 性能调优
├── deploy/                            # 部署包（可独立分发）
└── tests/                             # 验证与测试

php/
├── Dockerfile                         # 多阶段 Docker 构建文件（源码编译 PHP-FPM）
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 预构建镜像拉取用
├── docker-entrypoint.sh               # 容器入口脚本
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 PHP-FPM 详细教程
├── DOCKER-USAGE.md                    # 📖 Docker 使用教程
├── conf/                              # PHP 配置文件
│   ├── php.ini                       # PHP 主配置文件（安全加固）
│   ├── php-fpm.conf                  # PHP-FPM 主配置
│   └── www.conf                      # PHP-FPM 进程池配置
├── deploy/                            # 部署包（可独立分发）
└── tests/                             # 验证与测试
```