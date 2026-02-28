# PHP-FPM Docker 安全部署使用指南

基于 CIS Docker Benchmark 标准的 PHP-FPM 安全容器化部署方案。

> 📖 本文档为 Docker 使用教程，适用于直接拉取预构建镜像进行部署。
> 如需了解编译构建流程，请参阅源码仓库：[mzwrt/copilot](https://github.com/mzwrt/copilot)。

## 目录

- [快速开始](#快速开始)
- [使用预构建镜像（推荐）](#使用预构建镜像推荐)
- [卷挂载说明](#卷挂载说明)
- [PHP 配置说明](#php-配置说明)
- [与 Nginx 集成](#与-nginx-集成)
- [PHP 扩展管理](#php-扩展管理)
- [日常运维](#日常运维)
- [常见问题](#常见问题)

---

## 快速开始

```bash
# 1. 创建工作目录
mkdir php-docker && cd php-docker

# 2. 下载 docker-compose.yml（或从仓库复制）
# 修改 image 为你的镜像地址

# 3. 启动容器
docker compose up -d

# 4. 验证
docker exec php php -v
docker exec php php -m
```

## 使用预构建镜像（推荐）

### 步骤 1：登录 Docker Hub（私有仓库需要）

如果镜像仓库是公开的，可跳过此步骤。

```bash
echo "你的TOKEN" > ~/.dockerhub_token
cat ~/.dockerhub_token | docker login -u 你的DockerHub用户名 --password-stdin
rm ~/.dockerhub_token
```

### 步骤 2：配置 docker-compose.yml

修改 `image` 为你的镜像地址：

```yaml
services:
  php:
    image: <你的用户名>/php-fpm:latest
```

### 步骤 3：启动

```bash
docker compose up -d

# 查看状态
docker compose ps

# 查看日志
docker compose logs -f php
```

### 步骤 4：验证

```bash
# 查看 PHP 版本
docker exec php php -v

# 查看已加载扩展
docker exec php php -m

# 查看容器状态
docker ps
```

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `php-conf` | `/opt/php/etc` | PHP 配置文件 |
| `php-logs` | `/opt/php/var/log` | PHP-FPM 日志文件 |
| `wwwroot` | `/www/wwwroot` | 网站根目录（与 Nginx 共享） |

### 查看卷位置

```bash
docker volume inspect php-conf
```

### 编辑配置文件

```bash
# 方法1：进入容器
docker exec -it php /bin/bash

# 方法2：从宿主机复制
docker cp php:/opt/php/etc/php.ini ./php.ini
# 编辑后复制回去
docker cp ./php.ini php:/opt/php/etc/php.ini
docker restart php
```

---

## PHP 配置说明

### 配置文件结构

```
/opt/php/
├── etc/
│   ├── php.ini                       # PHP 主配置文件
│   ├── php-fpm.conf                  # PHP-FPM 主配置
│   ├── php-fpm.d/
│   │   └── www.conf                  # 进程池配置
│   └── conf.d/
│       ├── 10-opcache.ini            # OPcache 扩展
│       ├── 20-redis.ini              # Redis 扩展
│       ├── 20-memcached.ini          # Memcached 扩展
│       └── 20-imagick.ini            # ImageMagick 扩展
├── var/
│   ├── log/
│   │   ├── php-fpm.log              # PHP-FPM 日志
│   │   ├── php_error.log            # PHP 错误日志
│   │   └── php-fpm-slow.log         # 慢日志
│   └── run/
│       └── php-fpm.pid              # PID 文件
└── bin/
    └── php                           # PHP CLI
```

### 默认配置

- **安全加固**：`expose_php=Off`、`disable_functions` 已配置、`allow_url_include=Off`
- **性能优化**：OPcache 已启用（含 JIT）
- **生产配置**：`display_errors=Off`、`log_errors=On`
- **文件上传**：`upload_max_filesize=50M`
- **时区**：`date.timezone=Asia/Shanghai`

---

## 与 Nginx 集成

### 通过 Docker 网络连接

在同一个 `docker-compose.yml` 或通过外部网络连接：

```yaml
services:
  nginx:
    # ... 现有配置 ...
    depends_on:
      - php

  php:
    image: <你的用户名>/php-fpm:latest
    container_name: php
    volumes:
      - wwwroot:/www/wwwroot
    networks:
      - nginx-network
```

Nginx 站点配置：

```nginx
location ~ [^/]\.php(/|$) {
    try_files $uri =404;
    fastcgi_pass php:36000;
    fastcgi_index index.php;
    include fastcgi.conf;
    include php/pathinfo.conf;
}
```

---

## PHP 扩展管理

### 查看已加载扩展

```bash
docker exec php php -m
```

### 默认扩展

内置扩展：mysqlnd, mysqli, pdo_mysql, pgsql, pdo_pgsql, openssl, curl, gd, zip, sodium, mbstring, intl, bcmath, opcache, pcntl, sockets, exif, soap, tidy, xsl 等。

PECL 扩展（默认）：Redis, Memcached, ImageMagick

---

## 日常运维

### 重启 PHP-FPM

```bash
docker restart php
```

### 查看日志

```bash
# PHP-FPM 日志
docker exec php tail -f /opt/php/var/log/php-fpm.log

# PHP 错误日志
docker exec php tail -f /opt/php/var/log/php_error.log

# Docker 容器日志
docker logs -f php
```

### 测试配置

```bash
docker exec php php-fpm -t
```

### 备份配置

```bash
for vol in php-conf php-logs; do
  docker run --rm -v ${vol}:/data -v $(pwd)/backup:/backup \
    alpine tar czf /backup/${vol}.tar.gz -C /data .
done
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

**A**: 检查日志 `docker logs php`，常见原因：
1. PHP-FPM 配置语法错误
2. 文件权限不正确

### Q: PHP-FPM 连接超时

**A**: 确认 Nginx 和 PHP-FPM 在同一 Docker 网络中：
```bash
docker network ls
docker network inspect nginx-network
```

### Q: 如何查看已编译的扩展

```bash
docker exec php php -m
```

### Q: 如何进入容器调试

```bash
docker exec -it php /bin/bash
```

---

## 镜像版本标签

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `php-fpm:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `php-fpm:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `php-fpm:1.0` |
| `php-8.4.4` | 所有构建 | `php-fpm:php-8.4.4` |
