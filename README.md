# Nginx + PHP-FPM + Redis + PostgreSQL Docker 安全部署方案

基于 CIS Docker Benchmark、CIS Nginx Benchmark、CIS PostgreSQL Benchmark 和 PCI DSS v4.0 标准的 Nginx + PHP-FPM + Redis + PostgreSQL 安全容器化部署方案。

## 项目概述

本项目提供一套**生产级**的 Web 应用基础设施 Docker 安全部署方案，包含四个核心组件：

| 组件 | 说明 | 端口 | 详细教程 |
|------|------|------|---------|
| **Nginx** | 高性能 Web 服务器 + 反向代理 + WAF | 80/443（对外） | [nginx/README.md](nginx/README.md) |
| **PHP-FPM** | PHP 应用执行引擎 | 36000（内部） | [php/README.md](php/README.md) |
| **Redis** | 高性能内存数据库 / Session / 缓存 | 36379（内部） | [redis/README.md](redis/README.md) |
| **PostgreSQL** | 高性能关系型数据库 | 55432（内部） | [postgresql/README.md](postgresql/README.md) |

> ⚠️ PHP-FPM、Redis 和 PostgreSQL 均使用高位端口（36000、36379、55432），避免与常见服务冲突，增强安全性。

---

## 架构概览

```
                  ┌────────── Docker Network: nginx-network ──────────┐
                  │                                                   │
  客户端请求 ───▶ │  ┌─────────┐  TCP:36000  ┌─────────────┐         │
  HTTP/HTTPS      │  │  Nginx  │ ──────────▶ │  PHP-FPM    │         │
  :80 / :443      │  │ 容器    │             │  容器        │         │
                  │  └─────────┘             └──────┬──────┘         │
                  │       │                    ┌────┴────┐            │
                  │       │                    │         │            │
                  │       │               TCP:36379  TCP:55432        │
                  │       │                    │         │            │
                  │       │             ┌──────▼───┐ ┌──▼──────────┐ │
                  │       │             │  Redis   │ │ PostgreSQL  │ │
                  │       │             │  容器    │ │ 容器        │ │
                  │       │             └──────────┘ └─────────────┘ │
                  │       ▼                    ▼                      │
                  │  ┌──────────────────────────────────┐            │
                  │  │   共享卷: wwwroot                │            │
                  │  │   /www/wwwroot                   │            │
                  │  └──────────────────────────────────┘            │
                  └──────────────────────────────────────────────────┘
```

**工作原理**：
1. 客户端发送 HTTP/HTTPS 请求到 Nginx（端口 80/443）
2. Nginx 处理静态文件（HTML、CSS、JS、图片等）直接返回
3. 当请求 `.php` 文件时，Nginx 通过 FastCGI 协议将请求转发到 PHP-FPM（TCP 36000 端口）
4. PHP-FPM 执行 PHP 脚本，可通过 Redis 扩展连接 Redis（TCP 36379 端口）进行缓存/Session 存储
5. PHP-FPM 可通过 PDO/pg_connect 连接 PostgreSQL（TCP 55432 端口）进行数据持久化存储
6. PHP-FPM 将结果返回给 Nginx，Nginx 将响应返回给客户端

**关键集成点**：
- **网络通信**：四个容器通过 Docker 网络 `nginx-network` 使用各自端口通信
- **文件共享**：Nginx 和 PHP-FPM 共享 `wwwroot` 卷（挂载到 `/www/wwwroot`）
- **PHP-FPM 不暴露端口**：仅通过 Docker 内部网络访问
- **Redis 不暴露端口**：仅通过 Docker 内部网络供 PHP-FPM 访问
- **PostgreSQL 不暴露端口**：仅通过 Docker 内部网络供 PHP-FPM 访问

---

## 快速开始

### 方式一：使用预构建镜像（推荐）

镜像由 GitHub Actions 自动构建并发布到 Docker Hub，无需本地编译。

```bash
# 先修改各 docker-compose.ghcr.yml 中的 image 地址，然后：

# 启动 Redis
cd redis && docker compose -f docker-compose.ghcr.yml up -d && cd ..

# 启动 PostgreSQL
cd postgresql && docker compose -f docker-compose.ghcr.yml up -d && cd ..

# 启动 PHP-FPM
cd php && docker compose -f docker-compose.ghcr.yml up -d && cd ..

# 启动 Nginx
cd nginx && docker compose -f docker-compose.ghcr.yml up -d && cd ..
```

### 方式二：本地构建

在本地从源码编译所有组件（首次构建耗时较长）。

```bash
# 构建并启动 Redis
cd redis && docker compose up -d && cd ..

# 构建并启动 PostgreSQL
cd postgresql && docker compose up -d && cd ..

# 构建并启动 PHP-FPM
cd php && docker compose up -d && cd ..

# 构建并启动 Nginx
cd nginx && docker compose up -d && cd ..
```

### 验证部署

```bash
# 检查所有容器状态
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 验证网络连通性
docker network inspect nginx-network

# 测试 HTTP
curl http://localhost/

# 运行各组件验证脚本
bash nginx/tests/validate.sh
bash php/tests/validate.sh
bash redis/tests/validate.sh
bash postgresql/tests/validate.sh
```

---

## Nginx + PHP-FPM + Redis + PostgreSQL 联合部署教程

本章节详细说明如何将四个容器配合使用，实现完整的 PHP Web 应用部署方案，同时满足 CIS Docker Benchmark 和 PCI DSS v4.0 安全合规要求。

### 步骤 1：按顺序启动容器

四个容器必须按依赖顺序启动（Redis → PostgreSQL → PHP-FPM → Nginx）：

```bash
# 1. 先启动 Redis（PHP-FPM 可能需要连接 Redis）
cd redis
docker compose up -d
cd ..

# 2. 启动 PostgreSQL（PHP-FPM 可能需要连接数据库）
cd postgresql
docker compose up -d
cd ..

# 3. 再启动 PHP-FPM（Nginx 依赖 PHP-FPM 的 DNS 解析）
cd php
docker compose up -d
cd ..

# 4. 最后启动 Nginx
cd nginx
docker compose up -d
cd ..
```

> **重要说明**：四个 docker-compose 文件都定义了同名的网络 `nginx-network`。Docker 会自动复用已存在的同名网络，因此四个容器会自动加入同一网络。

### 步骤 2：验证集成

```bash
# 1. 检查四个容器是否在同一网络
docker network inspect nginx-network

# 2. 检查 PHP-FPM 是否正常监听
docker exec php ss -tlnp | grep 36000

# 3. 检查 Redis 是否正常运行
docker exec redis /opt/redis/bin/redis-cli -p 36379 ping

# 4. 检查 PostgreSQL 是否正常运行
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432

# 5. 检查 Nginx 能否解析其他容器名
docker exec nginx ping -c 1 php
docker exec nginx ping -c 1 redis
docker exec nginx ping -c 1 postgresql

# 6. 创建测试 PHP 文件
docker exec php sh -c 'echo "<?php phpinfo(); ?>" > /www/wwwroot/html/test.php'
```

### 步骤 3：配置 Nginx 站点启用 PHP

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

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    # 启用 PHP-FPM（通过 Docker 网络 TCP 通信，端口 36000）
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

### 步骤 4：PHP 连接 Redis

在 PHP 应用中连接 Redis（通过 Docker 网络内部通信）：

```php
<?php
// Redis 连接配置
$redis = new Redis();
$redis->connect('redis', 36379);  // Docker 容器名:端口

// 如果设置了密码
// $redis->auth('your_password');

// 测试连接
echo $redis->ping();  // 输出: +PONG

// 使用 Redis 作为 Session 存储
ini_set('session.save_handler', 'redis');
ini_set('session.save_path', 'tcp://redis:36379');
// 如果设置了密码:
// ini_set('session.save_path', 'tcp://redis:36379?auth=your_password');
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

    # CIS 4.1.13 / PCI DSS 4.2.1 - HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # CIS 5.3.1 - 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "0" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; frame-ancestors 'self'" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;

    root /www/wwwroot/html;
    index index.php index.html;

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

---

## CIS 和 PCI DSS 安全合规清单

Nginx + PHP-FPM + Redis + PostgreSQL 联合部署在以下安全基准方面已做加固：

### 容器级安全（CIS Docker Benchmark v1.6.0）

| CIS 编号 | 安全要求 | Nginx | PHP-FPM | Redis | PostgreSQL | 说明 |
|----------|---------|:-----:|:-------:|:-----:|:----------:|------|
| 5.3 | cap_drop: ALL | ✅ | ✅ | ✅ | ✅ | 丢弃所有 Linux 能力，仅添加必要能力 |
| 5.4 | 非特权模式运行 | ✅ | ✅ | ✅ | ✅ | 未使用 --privileged |
| 5.10 | 内存限制 | ✅ 2G | ✅ 2G | ✅ 2G | ✅ 4G | 防止内存耗尽攻击 |
| 5.11 | CPU 限制 | ✅ 4.0 | ✅ 4.0 | ✅ 4.0 | ✅ 4.0 | 防止 CPU 耗尽攻击 |
| 5.12 | 只读根文件系统 | ✅ | ✅ | ✅ | ✅ | read_only: true |
| 5.18 | 限制共享内存 | ✅ 256m | ✅ 256m | ✅ 256m | ✅ 512m | shm_size 限制 |
| 5.25 | no-new-privileges | ✅ | ✅ | ✅ | ✅ | 禁止获取新权限 |
| 5.26 | 健康检查 | ✅ | ✅ | ✅ | ✅ | 定期检测服务状态 |
| 5.28 | PID 限制 | ✅ 200 | ✅ 200 | ✅ 200 | ✅ 300 | 防止 Fork 炸弹 |

### 网络安全（CIS Nginx Benchmark v2.0.1 / PCI DSS v4.0）

| 安全项 | 配置 | 说明 |
|--------|------|------|
| TLS 版本 | TLSv1.2 + TLSv1.3 | PCI DSS 4.1 - 禁用 TLS 1.0/1.1 |
| 密码套件 | AEAD 优先 | CIS 4.1.4 - 使用安全密码套件 |
| HSTS | max-age=31536000 | PCI DSS 4.2.1 - 强制 HTTPS |
| 安全响应头 | X-Frame-Options 等 | CIS 5.3.1 - 防止 XSS/点击劫持 |
| 版本隐藏 | server_tokens off | CIS 5.1.2 - 隐藏 Nginx 版本 |
| PHP 版本隐藏 | expose_php = Off | 隐藏 PHP 版本信息 |
| WAF 防护 | ModSecurity + OWASP CRS | 应用层防火墙 |

### 应用安全

| 安全项 | 配置 | 说明 |
|--------|------|------|
| PHP 危险函数禁用 | disable_functions | 禁用 exec/system/passthru 等 |
| PHP 远程包含 | allow_url_include = Off | 防止远程代码包含 |
| Cookie 安全 | session.cookie_secure = 1 | PCI DSS - 仅 HTTPS 传输 Cookie |
| Cookie HttpOnly | session.cookie_httponly = 1 | 防止 XSS 窃取 Cookie |
| Session 严格模式 | session.use_strict_mode = 1 | 防止 Session 固定攻击 |
| PHP 环境变量清理 | clear_env = yes | PHP-FPM 进程隔离 |
| Redis 密码认证 | requirepass | 防止未授权访问 |
| Redis 危险命令重命名 | rename-command | 禁用 FLUSHDB/FLUSHALL/DEBUG |
| Redis protected-mode | protected-mode yes | 防止外部未授权连接 |
| Redis ACL | 用户级访问控制 | Redis 7.x 细粒度权限管理（可选） |
| PostgreSQL scram-sha-256 | password_encryption | 最安全的密码认证方式 |
| PostgreSQL HBA 规则 | pg_hba.conf | 限制连接源和认证方式 |
| PostgreSQL 行级安全 | row_security = on | 支持行级访问控制 |
| PostgreSQL 审计日志 | log_connections/log_statement | PCI DSS 10.2 审计合规 |
| PostgreSQL 搜索路径 | search_path = '"$user"' | 防止恶意对象注入（CIS 3.2） |
| PostgreSQL 数据校验和 | --data-checksums | 数据完整性保护 |

### 可选安全模块

以下安全模块默认关闭，可在构建时通过 `--build-arg` 启用：

#### PHP Snuffleupagus 安全扩展

[Snuffleupagus](https://snuffleupagus.readthedocs.io/) 是一个 PHP 运行时安全加固模块（Suhosin 的现代替代品），提供以下防护：

| 防护功能 | 说明 |
|---------|------|
| Cookie 加固 | 自动为所有 Cookie 设置 HttpOnly + Secure + SameSite |
| XXE 防护 | 全局禁用 XML 外部实体处理 |
| Session 加密 | 使用 sodium 库自动加密 Session 数据 |
| 邮件注入防护 | 限制 mail() 函数的发送源 |
| 运行时配置锁定 | 阻止通过 ini_set() 降低安全级别 |

**启用方式**：

```bash
# 构建时启用
docker build --build-arg USE_snuffleupagus=true -t php-fpm:latest ./php/

# 指定版本
docker build --build-arg USE_snuffleupagus=true --build-arg SNUFFLEUPAGUS_VERSION=0.10.0 -t php-fpm:latest ./php/
```

安全规则文件位于 `php/conf/snuffleupagus.rules`，可根据应用需求自定义。

#### Redis ACL (Access Control List)

Redis 7.x 原生支持 ACL 用户管理，提供比 `requirepass` 更细粒度的访问控制：

```redis
# 创建只读用户
user readonly_user on >readonly_password ~* &* +@read -@write -@admin -@dangerous

# 创建应用用户（允许读写，禁止管理命令）
user app_user on >app_password ~app:* &* +@read +@write -@admin -@dangerous
```

ACL 配置已在 `redis/conf/redis.conf` 中提供注释示例，取消注释即可启用。

### 容器间通信安全

| 安全项 | 配置 | 说明 |
|--------|------|------|
| 网络隔离 | 专用 nginx-network | Docker bridge 网络隔离，非 host 模式 |
| 高位端口 | PHP:36000 Redis:36379 PG:55432 | 避免常见端口扫描，增强安全性 |
| 端口限制 | PHP-FPM / Redis / PostgreSQL 不暴露端口 | 仅通过 Docker 内部网络通信 |
| 共享卷最小化 | 仅 Nginx+PHP 共享 wwwroot | Redis、PostgreSQL 使用独立数据卷 |
| 日志隔离 | 各自独立日志卷 | nginx-logs、php-logs、redis-logs、postgresql-logs 分别挂载 |

---

## 单独使用教程

每个组件都可以独立部署和使用，详细教程请参阅各自的 README：

### Nginx 单独使用

```bash
cd nginx
docker compose up -d          # 本地构建
# 或
docker compose -f docker-compose.ghcr.yml up -d  # 拉取预构建镜像
```

> 📖 详细教程: [nginx/README.md](nginx/README.md)

### PHP-FPM 单独使用

```bash
cd php
docker compose up -d          # 本地构建
# 或
docker compose -f docker-compose.ghcr.yml up -d  # 拉取预构建镜像
```

> 📖 详细教程: [php/README.md](php/README.md)

### Redis 单独使用

```bash
cd redis
docker compose up -d          # 本地构建
# 或
docker compose -f docker-compose.ghcr.yml up -d  # 拉取预构建镜像
```

> 📖 详细教程: [redis/README.md](redis/README.md)

### PostgreSQL 单独使用

```bash
cd postgresql
docker compose up -d          # 本地构建
# 或
docker compose -f docker-compose.ghcr.yml up -d  # 拉取预构建镜像
```

> 📖 详细教程: [postgresql/README.md](postgresql/README.md)

---

## 常见问题

### Q: Nginx 无法连接 PHP-FPM

**A**: 检查以下几点：

```bash
# 1. 确认两个容器在同一网络
docker network inspect nginx-network | grep -A2 '"Name"'

# 2. 确认 PHP-FPM 容器正在运行且监听 36000 端口
docker exec php ss -tlnp | grep 36000

# 3. 确认 Nginx 能解析 PHP 容器名
docker exec nginx getent hosts php

# 4. 检查 Nginx 错误日志
docker exec nginx tail -20 /opt/nginx/logs/nginx_error.log
```

### Q: PHP 无法连接 Redis

**A**: 检查以下几点：

```bash
# 1. 确认 Redis 容器正在运行
docker exec redis /opt/redis/bin/redis-cli -p 36379 ping

# 2. 确认 PHP 能解析 Redis 容器名
docker exec php getent hosts redis

# 3. 确认 PHP Redis 扩展已加载
docker exec php php -m | grep redis
```

### Q: PHP 无法连接 PostgreSQL

**A**: 检查以下几点：

```bash
# 1. 确认 PostgreSQL 容器正在运行
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432

# 2. 确认 PHP 能解析 PostgreSQL 容器名
docker exec php getent hosts postgresql

# 3. 确认 PHP pgsql/PDO_pgsql 扩展已加载
docker exec php php -m | grep -i pgsql

# 4. 确认 PostgreSQL 密码已设置
docker exec postgresql /opt/postgresql/bin/psql -U postgres -h 127.0.0.1 -p 55432 -c "SELECT 1;"
```

### Q: PHP 文件显示源码而不是执行

**A**: 确认站点配置中已包含 PHP 处理：
```nginx
# 在 server {} 块中添加
include php/enable-php-84.conf;
```

### Q: 文件权限问题（Permission Denied）

**A**: 确保网站文件属于 `www-data` 用户：
```bash
docker exec php chown -R www-data:www-data /www/wwwroot/html
docker exec php chmod 755 /www/wwwroot/html
```

### Q: 容器启动后立即退出

**A**: 检查日志：
```bash
docker logs nginx
docker logs php
docker logs redis
docker logs postgresql
```

常见原因：配置文件语法错误、文件权限不正确、依赖库缺失。

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
    ├── docker-build-push.yml              # Nginx GitHub Actions 构建发布工作流
    ├── docker-build-push-php.yml          # PHP-FPM GitHub Actions 构建发布工作流
    ├── docker-build-push-redis.yml        # Redis GitHub Actions 构建发布工作流
    └── docker-build-push-postgresql.yml   # PostgreSQL GitHub Actions 构建发布工作流

nginx/
├── Dockerfile                         # 多阶段 Docker 构建文件
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 预构建镜像拉取用
├── docker-entrypoint.sh               # 容器入口脚本
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 Nginx 详细教程
├── DOCKER-USAGE.md                    # 📖 Docker 使用教程
├── conf/                              # Nginx 配置文件
│   ├── nginx.conf                    # 主配置文件
│   ├── proxy.conf                    # 反向代理和缓存配置
│   ├── php/
│   │   ├── enable-php-84.conf        # PHP-FPM FastCGI 配置（TCP:36000）
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
│   └── www.conf                      # PHP-FPM 进程池配置（端口 36000）
├── deploy/                            # 部署包（可独立分发）
└── tests/                             # 验证与测试

redis/
├── Dockerfile                         # 多阶段 Docker 构建文件（源码编译 Redis）
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 预构建镜像拉取用
├── docker-entrypoint.sh               # 容器入口脚本
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 Redis 详细教程
├── conf/                              # Redis 配置文件
│   └── redis.conf                    # Redis 主配置文件（安全加固，端口 36379）
└── tests/                             # 验证与测试

postgresql/
├── Dockerfile                         # 多阶段 Docker 构建文件（源码编译 PostgreSQL）
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 预构建镜像拉取用
├── docker-entrypoint.sh               # 容器入口脚本
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 PostgreSQL 详细教程
├── conf/                              # PostgreSQL 配置文件
│   ├── postgresql.conf               # PostgreSQL 主配置文件（安全 + 性能加固，端口 55432）
│   └── pg_hba.conf                   # 主机认证配置文件（CIS 6.1 合规）
└── tests/                             # 验证与测试
```
