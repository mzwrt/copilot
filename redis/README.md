# Redis Docker 安全部署方案

基于 CIS Docker Benchmark 标准的 Redis 安全容器化部署方案。

## 目录

- [项目概述](#项目概述)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [部署教程](#部署教程)
  - [GitHub Actions 构建与 Docker Hub 拉取教程](#github-actions-构建与-docker-hub-拉取教程)
  - [本地构建教程](#本地构建教程)
- [构建参数](#构建参数)
- [卷挂载说明](#卷挂载说明)
- [与 PHP 和 Nginx 集成](#与-php-和-nginx-集成)
- [安全配置详解](#安全配置详解)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 项目概述

本项目提供一套**生产级**的 Redis Docker 安全部署方案，目标是：

- ✅ 通过 **CIS Docker Benchmark** 安全检查
- ✅ 源码编译 Redis，灵活控制编译选项（支持 TLS）
- ✅ 实施 **纵深防御**：Capabilities 限制 + 非 root 运行 + 只读文件系统
- ✅ 安全加固配置（危险命令重命名/禁用、密码认证、protected-mode）
- ✅ 使用高端口 36379 替代默认 6379，降低被扫描风险
- ✅ 与 PHP-FPM 和 Nginx 容器无缝集成

**核心安全特性**：

| 安全层面 | 实现方式 | 效果 |
|---------|---------|------|
| 容器级防护 | 非 root + 只读文件系统 + Capabilities 限制 | 最小权限原则 |
| 应用级防护 | 密码认证 + protected-mode + 危险命令禁用 | 减少攻击面 |
| 运维级防护 | 健康检查 + 日志收集 + 资源限制 + 内存限制 | 安全运维 |

## 目录结构

```
.github/
└── workflows/
    └── docker-build-push-redis.yml    # GitHub Actions 构建并发布到 Docker Hub

redis/
├── Dockerfile                         # 多阶段 Docker 构建（源码编译 Redis）
├── docker-compose.yml                 # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml            # Docker Compose - 拉取 Docker Hub 预构建镜像用
├── docker-entrypoint.sh               # 容器入口脚本（密码配置、健康检查）
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 📖 编译构建教程（本文件）
│
├── conf/                              # Redis 配置文件（内置，构建时 COPY 到镜像）
│   └── redis.conf                     # Redis 主配置文件（安全加固）
│
└── tests/
    └── validate.sh                    # 自动化安全验证脚本
```

## 快速开始

### 方式一：使用预构建镜像（推荐 - 从 Docker Hub 拉取）

镜像由 GitHub Actions 自动构建并发布到 Docker Hub，无需本地编译。

```bash
cd redis

# 拉取并启动（需先修改 docker-compose.ghcr.yml 中的镜像地址）
docker compose -f docker-compose.ghcr.yml up -d

# 查看容器状态
docker compose -f docker-compose.ghcr.yml ps

# 查看日志
docker compose -f docker-compose.ghcr.yml logs -f redis
```

### 方式二：本地构建

在本地从源码编译 Redis（编译耗时约 3-5 分钟）。

```bash
cd redis

# 构建镜像
docker compose build

# 启动容器
docker compose up -d
```

### 验证部署

```bash
# 运行安全验证脚本
bash tests/validate.sh

# 查看 Redis 版本
docker exec redis /opt/redis/bin/redis-server --version

# 测试 Redis 连接
docker exec redis /opt/redis/bin/redis-cli -p 36379 ping

# 查看日志
docker logs redis
```

---

## 部署教程

### GitHub Actions 构建与 Docker Hub 拉取教程

#### 概述

本项目提供 GitHub Actions 工作流（`.github/workflows/docker-build-push-redis.yml`），自动编译 Redis Docker 镜像并发布到 Docker Hub。

**优势**：
- ✅ 无需本地编译，节省时间和资源
- ✅ 自动化构建，每次代码更新自动发布新镜像
- ✅ 支持多架构（amd64/arm64）
- ✅ 支持版本标签管理

#### 步骤 1：配置 GitHub Secrets

在仓库 **Settings** → **Secrets and variables** → **Actions** 中添加：

| Secret 名称 | 说明 |
|-------------|------|
| `DOCKERHUB_USERNAME` | Docker Hub 用户名（例如 `ihccccom`） |
| `DOCKERHUB_TOKEN` | Docker Hub Access Token（在 Docker Hub → Account Settings → Security 中创建） |

> ⚠️ 三个镜像（Nginx、PHP-FPM、Redis）共用同一组 Secrets，只需配置一次。

#### 步骤 2：触发构建

构建会在以下情况自动触发：
- 推送到 `main` 分支且 `redis/` 目录有变更
- 创建版本标签（如 `v1.0.0`）

也可以手动触发：
1. 进入仓库页面 → **Actions** → **Build and Push Redis Docker Image**
2. 点击 **Run workflow**
3. 可选择配置 Redis 版本等
4. 点击 **Run workflow** 开始构建

#### 步骤 3：本地拉取并运行

```bash
cd redis

# 使用 docker-compose.ghcr.yml
docker compose -f docker-compose.ghcr.yml up -d

# 或手动拉取并运行
docker pull ihccccom/redis:latest
docker run -d --name redis ihccccom/redis:latest
```

#### 版本标签说明

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `redis:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `redis:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `redis:1.0` |
| `redis-7.4.4` | 所有构建 | `redis:redis-7.4.4` |

---

### 本地构建教程

#### 概述

在本地从源码编译构建 Redis Docker 镜像，适用于需要自定义编译选项或无法访问 Docker Hub 的场景。

**注意**：编译过程需要下载源码并编译，首次构建耗时约 **3-5 分钟**。

#### 步骤 1：克隆仓库

```bash
git clone https://github.com/mzwrt/copilot.git
cd copilot/redis
```

#### 步骤 2：（可选）自定义构建参数

编辑 `docker-compose.yml`，取消注释并修改 `args` 部分：

```yaml
services:
  redis:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        REDIS_VERSION: "7.4.4"
```

或者通过命令行传入构建参数：

```bash
docker compose build --build-arg REDIS_VERSION=7.4.4
```

#### 步骤 3：构建镜像

```bash
# 使用 docker compose 构建
docker compose build

# 或直接使用 docker build
docker build -t redis:latest .
```

#### 步骤 4：启动容器

```bash
docker compose up -d
docker compose ps
docker compose logs -f redis
```

#### 步骤 5：验证

```bash
# 查看 Redis 版本
docker exec redis /opt/redis/bin/redis-server --version

# 测试连接
docker exec redis /opt/redis/bin/redis-cli -p 36379 ping

# 运行安全检查
bash tests/validate.sh
```

## 构建参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `REDIS_VERSION` | `7.4.4` | Redis 版本号 |

**自定义构建示例**：

```bash
# 基本构建
docker build -t redis:latest ./redis/

# 指定 Redis 版本
docker build --build-arg REDIS_VERSION=7.2.7 -t redis:latest ./redis/
```

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `redis-conf` | `/opt/redis/etc` | Redis 配置文件（redis.conf） |
| `redis-data` | `/opt/redis/data` | Redis 数据目录（RDB + AOF 持久化文件） |
| `redis-logs` | `/opt/redis/var/log` | Redis 日志文件 |

## 与 PHP 和 Nginx 集成

Redis 容器需要与 PHP-FPM 容器配合使用，通过 Docker 网络通信。

### 网络配置

Redis、PHP-FPM 和 Nginx 容器需要在同一个 Docker 网络中：

```yaml
# redis/docker-compose.yml 中
networks:
  - nginx-network

# php/docker-compose.yml 中
networks:
  - nginx-network

# nginx/docker-compose.yml 中
networks:
  - nginx-network
```

### PHP 连接 Redis

在 PHP 代码中连接 Redis：

```php
<?php
$redis = new Redis();
// 使用容器名称 "redis" 作为主机名，端口 36379
$redis->connect('redis', 36379);
// 如果配置了密码
$redis->auth('your_password');
$redis->set('key', 'value');
echo $redis->get('key');
```

## 安全配置详解

### 危险命令处理

| 命令 | 处理方式 | 说明 |
|------|---------|------|
| `FLUSHDB` | 禁用（重命名为空） | 防止误删数据库 |
| `FLUSHALL` | 禁用（重命名为空） | 防止误删所有数据库 |
| `DEBUG` | 禁用（重命名为空） | 防止调试信息泄露 |
| `CONFIG` | 重命名为 `CONFIG_b4d8f2a1` | 限制运行时配置修改 |
| `SHUTDOWN` | 重命名为 `SHUTDOWN_b4d8f2a1` | 防止意外关闭 |

### 密码认证

通过环境变量 `REDIS_PASSWORD` 配置，在 `docker-compose.yml` 中取消注释：

```yaml
environment:
  REDIS_PASSWORD: "your_secure_password_here"
```

### 内存管理

- `maxmemory 512mb` - 限制最大内存使用
- `maxmemory-policy allkeys-lru` - LRU 淘汰策略

### 持久化

- **RDB 快照**：自动定期保存
- **AOF 日志**：每秒同步，保证数据安全

## 常见问题

### Q: 容器启动后立即退出

**A**: 检查日志 `docker logs redis`，常见原因：
1. Redis 配置语法错误
2. 文件权限不正确
3. 端口被占用

### Q: Redis 连接被拒绝

**A**: 确保 PHP 和 Redis 在同一 Docker 网络：
```bash
docker network ls
docker network inspect nginx-network
```

### Q: 如何设置 Redis 密码

**A**: 在 `docker-compose.yml` 中设置环境变量：
```yaml
environment:
  REDIS_PASSWORD: "your_secure_password_here"
```

### Q: 如何查看 Redis 信息

```bash
docker exec redis /opt/redis/bin/redis-cli -p 36379 info
```

### Q: 如何进入容器调试

```bash
docker exec -it redis /bin/bash
```

### Q: 如何连接到 Redis CLI

```bash
# 无密码
docker exec -it redis /opt/redis/bin/redis-cli -p 36379

# 有密码
docker exec -it redis /opt/redis/bin/redis-cli -p 36379 -a "your_password"
```

## 许可证

本项目遵循 [MIT License](../LICENSE)。
