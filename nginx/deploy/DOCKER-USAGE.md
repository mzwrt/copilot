# Nginx Docker 安全部署使用指南

基于 CIS Docker Benchmark、CIS Nginx Benchmark 标准的 Nginx 安全容器化部署方案。

> 📖 本文档为 Docker 使用教程，适用于直接拉取预构建镜像进行部署。
> 如需了解编译构建流程，请参阅源码仓库：[mzwrt/copilot](https://github.com/mzwrt/copilot)。

## 目录

- [快速开始](#快速开始)
- [使用预构建镜像（推荐）](#使用预构建镜像推荐)
- [卷挂载说明](#卷挂载说明)
- [Nginx 配置说明](#nginx-配置说明)
- [ModSecurity WAF 使用](#modsecurity-waf-使用)
- [OWASP CRS 规则集](#owasp-crs-规则集)
- [PHP 集成](#php-集成)
- [添加网站](#添加网站)
- [SSL 证书配置](#ssl-证书配置)
- [安全配置](#安全配置)
- [日常运维](#日常运维)
- [常见问题](#常见问题)

---

## 快速开始

```bash
# 1. 创建工作目录
mkdir nginx-docker && cd nginx-docker

# 2. 下载 docker-compose.yml（或从仓库复制）
# 修改 image 为你的镜像地址

# 3. 启动容器
docker compose up -d

# 4. 验证
curl http://localhost/
curl -k https://localhost/
```

## 使用预构建镜像（推荐）

### 步骤 1：登录 Docker Hub（私有仓库需要）

如果镜像仓库是公开的，可跳过此步骤。

```bash
# 将 Token 保存到文件，避免在命令行直接暴露
echo "你的TOKEN" > ~/.dockerhub_token
cat ~/.dockerhub_token | docker login -u 你的DockerHub用户名 --password-stdin
rm ~/.dockerhub_token
```

### 步骤 2：配置 docker-compose.yml

修改 `image` 为你的镜像地址：

```yaml
services:
  nginx:
    image: ihccccom/nginx:latest
```

### 步骤 3：启动

```bash
docker compose up -d

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f nginx
```

### 步骤 4：验证

```bash
# HTTP 测试
curl http://localhost/

# HTTPS 测试（自签名证书）
curl -k https://localhost/

# 查看容器状态
docker ps
```

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `nginx-conf` | `/opt/nginx/conf` | Nginx 配置文件（nginx.conf、proxy.conf 等） |
| `nginx-confd` | `/opt/nginx/conf.d` | 网站配置文件（sites-available/sites-enabled） |
| `nginx-ssl` | `/opt/nginx/ssl` | SSL 证书文件 |
| `nginx-logs` | `/opt/nginx/logs` | 日志文件（访问日志、错误日志、WAF 审计日志） |
| `wwwroot` | `/www/wwwroot` | 网站根目录 |
| `owasp` | `/opt/owasp` | OWASP 规则集 |
| `nginx-cache` | `/var/cache/nginx` | Nginx 缓存目录 |

### 查看卷位置

```bash
docker volume inspect nginx-conf
```

### 编辑配置文件

```bash
# 方法1：进入容器
docker exec -it nginx /bin/bash

# 方法2：从宿主机复制
docker cp nginx:/opt/nginx/conf/nginx.conf ./nginx.conf
# 编辑后复制回去
docker cp ./nginx.conf nginx:/opt/nginx/conf/nginx.conf
docker exec nginx /opt/nginx/sbin/nginx -s reload
```

---

## Nginx 配置说明

### 配置文件结构

```
/opt/nginx/
├── conf/
│   ├── nginx.conf                    # 主配置文件
│   ├── proxy.conf                    # 反向代理和缓存配置
│   ├── mime.types                    # MIME 类型配置
│   ├── php/
│   │   ├── pathinfo.conf            # PHP Pathinfo 支持
│   │   └── enable-php-84.conf       # PHP 8.4 FastCGI 配置
│   └── modsecurity/
│       ├── modsecurity.conf         # ModSecurity 主配置
│       ├── main.conf                # OWASP 规则引入配置
│       ├── crs-setup.conf           # OWASP CRS 偏好设置
│       ├── hosts.allow              # IP 白名单
│       └── hosts.deny               # IP 黑名单
├── conf.d/
│   ├── sites-available/             # 可用的网站配置
│   └── sites-enabled/               # 已启用的网站配置（符号链接）
├── ssl/
│   └── default/
│       ├── default.pem              # 默认自签名证书
│       └── default.key              # 默认私钥
└── logs/
    ├── nginx_error.log              # Nginx 错误日志
    ├── nginx.pid                    # PID 文件
    ├── modsec_audit.log             # ModSecurity 审计日志
    └── modsec_audit/                # ModSecurity 并发审计日志目录
```

### 默认行为

- **HTTP 80** 和 **HTTPS 443** 默认返回 444（拒绝未配置域名的请求）
- 已启用 Brotli + Gzip 压缩
- 已启用 ModSecurity WAF（OWASP CRS 规则集）
- 已配置反向代理缓存
- 已配置 SSL/TLS 安全加固（仅 TLS 1.2/1.3，AEAD 密码套件）
- 已配置安全响应头（HSTS、CSP、X-Frame-Options 等）
- 已配置请求速率限制（防暴力破解和 DDoS）

---

## ModSecurity WAF 使用

### 查看 WAF 是否工作

```bash
# 测试 XSS 攻击检测（应返回 403）
curl -o /dev/null -w "%{http_code}" "http://localhost/?q=<script>alert(1)</script>"

# 测试 SQL 注入检测（应返回 403）
curl -o /dev/null -w "%{http_code}" "http://localhost/?id=1%20OR%201=1--"
```

### 查看审计日志

```bash
# 进入容器查看
docker exec nginx cat /opt/nginx/logs/modsec_audit.log

# 或从宿主机
docker exec nginx ls -la /opt/nginx/logs/modsec_audit/
```

### 添加 IP 白名单

编辑 `/opt/nginx/conf/modsecurity/hosts.allow`：

```
SecRule REMOTE_ADDR "@ipMatch 192.168.1.100" "id:11001,phase:1,nolog,pass,ctl:ruleEngine=off"
```

### 添加 IP 黑名单

编辑 `/opt/nginx/conf/modsecurity/hosts.deny`：

```
SecRule REMOTE_ADDR "@ipMatch 10.0.0.5" "id:12001,phase:1,log,auditlog,deny,status:403"
```

### 排除特定规则

如果某个规则产生误报，可以在网站配置中排除：

```nginx
# 在 location 块中添加
modsecurity_rules '
    SecRuleRemoveById 942100
';
```

---

## OWASP CRS 规则集

### 偏好级别

当前配置为 **偏好级别 3**（高安全性），如需调整：

编辑 `/opt/nginx/conf/modsecurity/crs-setup.conf`：

```
# 偏好级别 1（默认，最少误报）
setvar:tx.blocking_paranoia_level=1

# 偏好级别 2（中级）
setvar:tx.blocking_paranoia_level=2

# 偏好级别 3（高安全性，当前值）
setvar:tx.blocking_paranoia_level=3

# 偏好级别 4（最高，大量误报）
setvar:tx.blocking_paranoia_level=4
```

### 启用 WordPress 排除规则

如果运行 WordPress 站点，取消注释 `/opt/nginx/conf/modsecurity/main.conf` 最后两行：

```
include /opt/owasp/owasp-rules/plugins/wordpress-rule-exclusions-before.conf
include /opt/owasp/owasp-rules/plugins/wordpress-rule-exclusions-config.conf
```

---

## PHP 集成

### 方式一：通过 Docker 网络连接 PHP-FPM 容器

在 `docker-compose.yml` 中添加 PHP-FPM 服务：

```yaml
services:
  nginx:
    # ... 现有配置 ...
    depends_on:
      - php-fpm

  php-fpm:
    image: php:8.4-fpm
    container_name: php-fpm
    volumes:
      - wwwroot:/www/wwwroot
    networks:
      - nginx-network
```

然后修改 `/opt/nginx/conf/php/enable-php-84.conf`，将 socket 改为 TCP：

```nginx
location ~ [^/]\.php(/|$) {
    try_files $uri =404;
    fastcgi_pass php:36000;
    fastcgi_index index.php;
    include fastcgi.conf;
    include php/pathinfo.conf;
}
```

### 方式二：使用 Unix Socket（同一容器或挂载 Socket）

如果 PHP-FPM 在同一主机上运行，可以通过挂载 socket 文件：

```yaml
volumes:
  - /run/php/php8.4-fpm.sock:/run/php/php8.4-fpm.sock
```

---

## 添加网站

### 步骤 1：创建网站配置文件

```bash
docker exec -it nginx /bin/bash
cat > /opt/nginx/conf.d/sites-available/example.com.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name example.com www.example.com;

    # 强制 HTTPS 跳转
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name example.com www.example.com;

    # SSL 证书
    ssl_certificate /opt/nginx/ssl/example.com/fullchain.pem;
    ssl_certificate_key /opt/nginx/ssl/example.com/privkey.pem;

    # SSL 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;

    # 安全响应头
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # 网站根目录
    root /www/wwwroot/example.com;
    index index.html index.php;

    # 启用 ModSecurity WAF
    modsecurity on;
    modsecurity_rules_file /opt/nginx/conf/modsecurity/main.conf;

    # 日志
    access_log /opt/nginx/logs/example.com_access.log;
    error_log /opt/nginx/logs/example.com_error.log;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # 启用 PHP（如需要，取消注释）
    # include php/enable-php-84.conf;

    # 禁止访问隐藏文件
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF
```

### 步骤 2：启用网站

```bash
# 创建符号链接
ln -sf /opt/nginx/conf.d/sites-available/example.com.conf \
       /opt/nginx/conf.d/sites-enabled/example.com.conf

# 测试配置
/opt/nginx/sbin/nginx -t

# 重载配置
/opt/nginx/sbin/nginx -s reload
```

---

## SSL 证书配置

### 使用 Let's Encrypt 证书

```bash
# 1. 在宿主机申请证书
certbot certonly --standalone -d example.com -d www.example.com

# 2. 复制证书到 Docker 卷
docker cp /etc/letsencrypt/live/example.com/fullchain.pem nginx:/opt/nginx/ssl/example.com/fullchain.pem
docker cp /etc/letsencrypt/live/example.com/privkey.pem nginx:/opt/nginx/ssl/example.com/privkey.pem

# 3. 设置权限
docker exec nginx chmod 400 /opt/nginx/ssl/example.com/privkey.pem
docker exec nginx chmod 600 /opt/nginx/ssl/example.com/fullchain.pem

# 4. 重载 Nginx
docker exec nginx /opt/nginx/sbin/nginx -s reload
```

### 使用自定义证书

将证书文件放入 `nginx-ssl` 卷中，目录结构建议：

```
/opt/nginx/ssl/
├── default/              # 默认自签名证书
├── example.com/          # 网站证书
│   ├── fullchain.pem
│   └── privkey.pem
└── another-site.com/
    ├── fullchain.pem
    └── privkey.pem
```

---

## 安全配置

### 容器运行时安全

docker-compose 已配置以下安全选项：

| 安全特性 | 配置 | 说明 |
|---------|------|------|
| 非特权模式 | `cap_drop: ALL` | 丢弃所有 Linux 能力 |
| 最小能力 | `cap_add: NET_BIND_SERVICE, ...` | 仅保留必要能力 |
| 防提权 | `no-new-privileges:true` | 禁止获取新权限 |
| 内存限制 | `2G` | 防止内存耗尽 |
| CPU 限制 | `4.0` | 防止 CPU 耗尽 |
| PID 限制 | `200` | 防止 Fork 炸弹 |

### 启用 Seccomp Profile

```yaml
security_opt:
  - no-new-privileges:true
  - seccomp=./security/seccomp/nginx-seccomp.json
```

### 启用 AppArmor Profile

```bash
# 1. 加载 Profile 到宿主机
sudo apparmor_parser -r security/apparmor/nginx-apparmor-profile

# 2. 在 docker-compose 中启用
security_opt:
  - apparmor=docker-nginx
```

---

## 日常运维

### 重载配置（不停机）

```bash
docker exec nginx /opt/nginx/sbin/nginx -s reload
```

### 查看日志

```bash
# Nginx 错误日志
docker exec nginx tail -f /opt/nginx/logs/nginx_error.log

# ModSecurity 审计日志
docker exec nginx tail -f /opt/nginx/logs/modsec_audit.log

# Docker 容器日志
docker logs -f nginx
```

### 测试配置文件

```bash
docker exec nginx /opt/nginx/sbin/nginx -t
```

### 备份配置

```bash
# 备份所有卷数据
for vol in nginx-conf nginx-confd nginx-ssl nginx-logs wwwroot owasp; do
  docker run --rm -v ${vol}:/data -v $(pwd)/backup:/backup \
    alpine tar czf /backup/${vol}.tar.gz -C /data .
done
```

### 恢复配置

```bash
# 从备份恢复
docker run --rm -v nginx-conf:/data -v $(pwd)/backup:/backup \
  alpine sh -c "cd /data && tar xzf /backup/nginx-conf.tar.gz"
```

### 更新镜像

```bash
# 拉取最新镜像
docker compose pull

# 重新创建容器（卷数据保留）
docker compose up -d
```

---

## 常见问题

### Q: 容器启动后立即退出

**A**: 检查日志 `docker logs nginx`，常见原因：
1. SSL 证书文件未挂载或路径错误
2. Nginx 配置语法错误
3. 文件权限不正确

### Q: HTTPS 证书错误

**A**: 确保证书路径正确且权限符合要求：
```bash
docker exec nginx ls -la /opt/nginx/ssl/default/
```

### Q: ModSecurity WAF 误报

**A**: 查看 ModSecurity 审计日志找到规则 ID，然后添加排除规则：
```nginx
modsecurity_rules '
    SecRuleRemoveById 942100
';
```

### Q: PHP 无法连接

**A**: 确保 PHP-FPM 容器在同一 Docker 网络中：
```bash
docker network ls
docker network inspect nginx-network
```

### Q: 如何查看 Nginx 编译模块

```bash
docker exec nginx /opt/nginx/sbin/nginx -V
```

### Q: 如何进入容器调试

```bash
docker exec -it nginx /bin/bash
```

---

## 镜像版本标签

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `nginx:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `nginx:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `nginx:1.0` |
| `nginx-1.28.2` | 所有构建 | `nginx:nginx-1.28.2` |
