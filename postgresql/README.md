# PostgreSQL Docker 安全部署方案

基于 CIS Docker Benchmark、CIS PostgreSQL Benchmark 和 PCI DSS v4.0 标准的 PostgreSQL 安全容器化部署方案。

## 目录

- [项目概述](#项目概述)
- [目录结构](#目录结构)
- [快速开始](#快速开始)
- [部署教程](#部署教程)
  - [GitHub Actions 构建与 Docker Hub 拉取教程](#github-actions-构建与-docker-hub-拉取教程)
  - [本地构建教程](#本地构建教程)
- [构建参数](#构建参数)
- [卷挂载说明](#卷挂载说明)
- [与 PHP、Nginx 和 Redis 集成](#与-php-nginx-和-redis-集成)
- [单独部署教程](#单独部署教程)
- [安全配置详解](#安全配置详解)
- [高性能配置详解](#高性能配置详解)
- [高可用配置](#高可用配置)
- [常见问题](#常见问题)
- [许可证](#许可证)

---

## 项目概述

本项目提供一套**生产级**的 PostgreSQL Docker 安全部署方案，目标是：

- ✅ 通过 **CIS Docker Benchmark** 安全检查
- ✅ 通过 **CIS PostgreSQL Benchmark** 安全检查
- ✅ 符合 **PCI DSS v4.0** 数据安全标准
- ✅ 源码编译 PostgreSQL，灵活控制编译选项（支持 SSL、PAM、LDAP、ICU、LZ4、ZSTD）
- ✅ 实施 **纵深防御**：Capabilities 限制 + 非 root 运行 + 只读文件系统
- ✅ 安全加固配置（scram-sha-256 认证、行级安全、审计日志、搜索路径限制）
- ✅ 使用高端口 55432 替代默认 5432，降低被扫描风险
- ✅ **高性能**配置（共享缓冲区、并行查询、JIT 编译、WAL 压缩）
- ✅ **高并发**支持（200 最大连接、16 工作进程、并行查询优化）
- ✅ **高可用**就绪（WAL 归档、流复制支持、数据校验和）
- ✅ 与 PHP-FPM、Nginx 和 Redis 容器无缝集成

**核心安全特性**：

| 安全层面 | 实现方式 | 效果 |
|---------|---------|------|
| 容器级防护 | 非 root + 只读文件系统 + Capabilities 限制 | 最小权限原则 |
| 认证安全 | scram-sha-256 + HBA 规则 + 认证超时 | 防止未授权访问和暴力破解 |
| 数据安全 | 数据校验和 + WAL 同步 + fsync | 数据完整性保护 |
| 审计安全 | 连接日志 + DDL 日志 + 慢查询日志 | PCI DSS 10.2 审计合规 |
| 运维级防护 | 健康检查 + 日志收集 + 资源限制 | 安全运维 |

## 目录结构

```
.github/
└── workflows/
    └── docker-build-push-postgresql.yml  # GitHub Actions 构建并发布到 Docker Hub

postgresql/
├── Dockerfile                             # 多阶段 Docker 构建（源码编译 PostgreSQL）
├── docker-compose.yml                     # Docker Compose - 本地构建用
├── docker-compose.ghcr.yml                # Docker Compose - 拉取 Docker Hub 预构建镜像用
├── docker-entrypoint.sh                   # 容器入口脚本（初始化、密码配置、健康检查）
├── .dockerignore                          # 构建上下文排除规则
├── README.md                              # 📖 编译构建教程（本文件）
│
├── conf/                                  # PostgreSQL 配置文件（内置，构建时 COPY 到镜像）
│   ├── postgresql.conf                    # PostgreSQL 主配置文件（安全 + 性能加固）
│   └── pg_hba.conf                        # 主机认证配置文件（CIS 6.1 合规）
│
└── tests/
    └── validate.sh                        # 自动化安全验证脚本
```

## 快速开始

### 方式一：使用预构建镜像（推荐 - 从 Docker Hub 拉取）

镜像由 GitHub Actions 自动构建并发布到 Docker Hub，无需本地编译。

```bash
cd postgresql

# 拉取并启动（需先修改 docker-compose.ghcr.yml 中的镜像地址）
docker compose -f docker-compose.ghcr.yml up -d

# 查看容器状态
docker compose -f docker-compose.ghcr.yml ps

# 查看日志
docker compose -f docker-compose.ghcr.yml logs -f postgresql
```

### 方式二：本地构建

在本地从源码编译 PostgreSQL（编译耗时约 5-10 分钟）。

```bash
cd postgresql

# 构建镜像
docker compose build

# 启动容器
docker compose up -d
```

### 验证部署

```bash
# 运行安全验证脚本
bash tests/validate.sh

# 查看 PostgreSQL 版本
docker exec postgresql /opt/postgresql/bin/postgres --version

# 测试 PostgreSQL 连接
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432

# 查看日志
docker logs postgresql
```

---

## 部署教程

### GitHub Actions 构建与 Docker Hub 拉取教程

#### 概述

本项目提供 GitHub Actions 工作流（`.github/workflows/docker-build-push-postgresql.yml`），自动编译 PostgreSQL Docker 镜像并发布到 Docker Hub。

**优势**：
- ✅ 无需本地编译，节省时间和资源
- ✅ 自动化构建，每次代码更新自动发布新镜像
- ✅ 支持多架构（amd64/arm64）
- ✅ 支持版本标签管理

#### 步骤 1：配置 GitHub Secrets

在仓库 **Settings** → **Secrets and variables** → **Actions** 中添加：

| Secret 名称 | 说明 |
|-------------|------|
| `docker_postgresql_USER` | Docker Hub 用户名 |
| `DOCKER_POSTGRESQL_TOKEN` | Docker Hub Access Token |

#### 步骤 2：触发构建

构建会在以下情况自动触发：
- 推送到 `main` 分支且 `postgresql/` 目录有变更
- 创建版本标签（如 `v1.0.0`）

也可以手动触发：
1. 进入仓库页面 → **Actions** → **Build and Push PostgreSQL Docker Image**
2. 点击 **Run workflow**
3. 可选择配置 PostgreSQL 版本等
4. 点击 **Run workflow** 开始构建

#### 步骤 3：本地拉取并运行

```bash
cd postgresql

# 使用 docker-compose.ghcr.yml
docker compose -f docker-compose.ghcr.yml up -d

# 或手动拉取并运行
docker pull <你的用户名>/postgresql:latest
docker run -d --name postgresql <你的用户名>/postgresql:latest
```

#### 版本标签说明

| 标签格式 | 触发条件 | 示例 |
|---------|---------|------|
| `latest` | 推送到 main 分支 | `postgresql:latest` |
| `v1.0.0` | 创建 v1.0.0 标签 | `postgresql:v1.0.0` |
| `1.0` | 创建 v1.0.x 标签 | `postgresql:1.0` |
| `pg-17.4` | 所有构建 | `postgresql:pg-17.4` |

---

### 本地构建教程

#### 概述

在本地从源码编译构建 PostgreSQL Docker 镜像，适用于需要自定义编译选项或无法访问 Docker Hub 的场景。

**注意**：编译过程需要下载源码并编译，首次构建耗时约 **5-10 分钟**。

#### 步骤 1：克隆仓库

```bash
git clone https://github.com/<你的用户名>/<你的仓库名>.git
cd <你的仓库名>/postgresql
```

#### 步骤 2：（可选）自定义构建参数

编辑 `docker-compose.yml`，取消注释并修改 `args` 部分：

```yaml
services:
  postgresql:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        PG_VERSION: "17.4"
```

或者通过命令行传入构建参数：

```bash
docker compose build --build-arg PG_VERSION=17.4
```

#### 步骤 3：构建镜像

```bash
# 使用 docker compose 构建
docker compose build

# 或直接使用 docker build
docker build -t postgresql:latest .
```

#### 步骤 4：启动容器

```bash
docker compose up -d
docker compose ps
docker compose logs -f postgresql
```

#### 步骤 5：验证

```bash
# 查看 PostgreSQL 版本
docker exec postgresql /opt/postgresql/bin/postgres --version

# 测试连接
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432

# 运行安全检查
bash tests/validate.sh
```

## 构建参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `PG_VERSION` | `17.4` | PostgreSQL 版本号 |

**自定义构建示例**：

```bash
# 基本构建
docker build -t postgresql:latest ./postgresql/

# 指定 PostgreSQL 版本
docker build --build-arg PG_VERSION=16.8 -t postgresql:latest ./postgresql/
```

**编译选项说明**：

| 编译选项 | 说明 |
|---------|------|
| `--with-openssl` | SSL/TLS 加密支持 |
| `--with-pam` | PAM 认证支持 |
| `--with-ldap` | LDAP 认证支持 |
| `--with-libxml` | XML 数据类型支持 |
| `--with-libxslt` | XSLT 转换支持 |
| `--with-uuid=e2fs` | UUID 数据类型支持 |
| `--with-icu` | 国际化排序支持 |
| `--with-lz4` | LZ4 压缩（高性能 WAL 压缩） |
| `--with-zstd` | ZSTD 压缩支持 |
| `--with-systemd` | systemd 集成支持 |

## 卷挂载说明

| 卷名 | 容器路径 | 说明 |
|------|---------|------|
| `postgresql-conf` | `/opt/postgresql/etc` | PostgreSQL 配置文件（postgresql.conf、pg_hba.conf） |
| `postgresql-data` | `/opt/postgresql/data` | PostgreSQL 数据目录（数据库文件） |
| `postgresql-wal` | `/opt/postgresql/wal` | PostgreSQL WAL 日志（预写日志，数据恢复用） |
| `postgresql-logs` | `/opt/postgresql/var/log` | PostgreSQL 日志文件 |

## 与 PHP、Nginx 和 Redis 集成

PostgreSQL 容器需要与其他容器配合使用，通过 Docker 网络通信。

### 网络配置

PostgreSQL、PHP-FPM、Redis 和 Nginx 容器需要在同一个 Docker 网络中：

```yaml
# postgresql/docker-compose.yml 中
networks:
  - nginx-network

# php/docker-compose.yml 中
networks:
  - nginx-network

# redis/docker-compose.yml 中
networks:
  - nginx-network

# nginx/docker-compose.yml 中
networks:
  - nginx-network
```

### 启动顺序

四个容器按依赖顺序启动（Redis → PostgreSQL → PHP-FPM → Nginx）：

```bash
# 1. 先启动 Redis
cd redis && docker compose up -d && cd ..

# 2. 启动 PostgreSQL
cd postgresql && docker compose up -d && cd ..

# 3. 启动 PHP-FPM
cd php && docker compose up -d && cd ..

# 4. 最后启动 Nginx
cd nginx && docker compose up -d && cd ..
```

### PHP 连接 PostgreSQL

在 PHP 代码中连接 PostgreSQL：

```php
<?php
// PDO 方式连接（推荐）
$dsn = 'pgsql:host=postgresql;port=55432;dbname=myapp';
$pdo = new PDO($dsn, 'myapp_user', 'your_password', [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    PDO::ATTR_EMULATE_PREPARES => false,  // 使用原生预处理语句（安全）
]);

// 测试连接
$stmt = $pdo->query('SELECT version()');
echo $stmt->fetchColumn();

// pg_connect 方式连接
$conn = pg_connect("host=postgresql port=55432 dbname=myapp user=myapp_user password=your_password");
if ($conn) {
    echo "PostgreSQL connection successful";
    $result = pg_query($conn, "SELECT version()");
    echo pg_fetch_result($result, 0, 0);
}
```

### PHP Session 存储到 PostgreSQL

```php
<?php
// 使用 PostgreSQL 作为 Session 存储（需要创建 session 表）
// CREATE TABLE sessions (
//     id VARCHAR(128) PRIMARY KEY,
//     data TEXT,
//     last_access TIMESTAMP DEFAULT CURRENT_TIMESTAMP
// );
```

---

## 单独部署教程

PostgreSQL 可以独立部署使用，不依赖其他容器。

### 独立部署 - 本地构建

```bash
cd postgresql

# 设置密码（强烈建议）
# 编辑 docker-compose.yml，取消注释 POSTGRES_PASSWORD

# 构建并启动
docker compose up -d

# 验证
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432
```

### 独立部署 - 暴露端口

如需从主机或外部访问 PostgreSQL，取消注释端口映射：

```yaml
# docker-compose.yml 中
ports:
  - "55432:55432"
```

### 独立部署 - 创建数据库和用户

```bash
# 进入 PostgreSQL 容器
docker exec -it postgresql /opt/postgresql/bin/psql -U postgres -h 127.0.0.1 -p 55432

# 创建数据库
CREATE DATABASE myapp;

# 创建用户（使用 scram-sha-256 密码）
CREATE USER myapp_user WITH PASSWORD 'secure_password_here';

# 授予权限
GRANT ALL PRIVILEGES ON DATABASE myapp TO myapp_user;
\c myapp
GRANT ALL ON SCHEMA public TO myapp_user;

# 创建只读用户（最小权限原则 - PCI DSS 7.2）
CREATE USER readonly_user WITH PASSWORD 'readonly_password_here';
GRANT CONNECT ON DATABASE myapp TO readonly_user;
\c myapp
GRANT USAGE ON SCHEMA public TO readonly_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly_user;
```

### 独立部署 - 使用环境变量自动创建

```yaml
# docker-compose.yml 中设置环境变量
environment:
  POSTGRES_PASSWORD: "your_secure_password_here"
  POSTGRES_DB: "myapp"
  POSTGRES_USER: "myapp_user"
```

容器首次启动时会自动：
1. 初始化数据库（启用数据校验和）
2. 设置超级用户密码
3. 创建指定的数据库和用户

---

## 安全配置详解

### 认证安全（CIS PostgreSQL Benchmark）

| CIS 编号 | 安全要求 | 配置 | 说明 |
|----------|---------|------|------|
| 6.1 | HBA 认证规则 | pg_hba.conf | 仅允许 Docker 网络 + scram-sha-256 |
| 6.2 | 认证超时 | 30s | 防止认证连接占用资源 |
| 6.5 | 行级安全 | row_security = on | 支持行级访问控制 |
| 6.7 | 密码加密 | scram-sha-256 | 最安全的密码认证方式 |
| 6.8 | 日志级别 | warning | 记录警告及以上级别 |
| 6.9 | 连接日志 | log_connections = on | 记录所有连接/断开事件 |
| 6.10 | 慢查询日志 | 1000ms | 记录超过 1 秒的查询 |
| 6.11 | 日志前缀 | 时间+用户+DB+客户端 | PCI DSS 10.2 审计信息 |
| 6.12 | DDL 日志 | log_statement = ddl | 记录所有 DDL 变更 |

### HBA 认证规则说明

```
# 连接类型  数据库  用户      地址            认证方式
local      all     postgres                  peer           # 本地超级用户：OS 用户验证
local      all     all                       scram-sha-256  # 本地其他用户：密码验证
host       all     all       172.16.0.0/12   scram-sha-256  # Docker 网络：密码验证
host       all     all       192.168.0.0/16  scram-sha-256  # Docker bridge：密码验证
host       all     all       127.0.0.1/32    scram-sha-256  # 本地回环：密码验证
```

**安全要点**：
- ❌ 不使用 `trust` 认证（任何情况下都不信任）
- ❌ 不使用 `md5` 认证（已被认为不安全）
- ❌ 不使用 `password` 明文认证
- ✅ 统一使用 `scram-sha-256`（最安全）
- ✅ 不开放 `0.0.0.0/0`（不允许所有地址）

### 数据安全

| 安全项 | 配置 | 说明 |
|--------|------|------|
| 数据校验和 | `--data-checksums` | initdb 时启用，检测数据损坏 |
| WAL 同步 | `synchronous_commit = on` | 确保事务持久性 |
| fsync | `fsync = on` | 确保数据写入磁盘 |
| 全页写入 | `full_page_writes = on` | 防止部分写入损坏 |
| 临时文件限制 | `temp_file_limit = 1GB` | 防止磁盘耗尽 |

### 搜索路径安全（CIS 3.2）

```sql
-- 默认搜索路径不包含 public schema
-- search_path = '"$user"'
-- 这可以防止恶意对象注入攻击（trojan objects in public schema）
```

---

## 高性能配置详解

### 内存配置

| 参数 | 值 | 说明 |
|------|-----|------|
| `shared_buffers` | 512MB | 共享缓冲区（容器内存 4G 的 12.5%） |
| `work_mem` | 16MB | 每个排序/哈希操作的内存 |
| `maintenance_work_mem` | 256MB | 维护操作（VACUUM 等）内存 |
| `effective_cache_size` | 1536MB | 查询优化器缓存估算 |
| `temp_buffers` | 32MB | 临时表缓冲区 |

### 并行查询配置

| 参数 | 值 | 说明 |
|------|-----|------|
| `max_parallel_workers_per_gather` | 4 | 每个查询最大并行工作进程 |
| `max_parallel_workers` | 8 | 最大并行工作进程总数 |
| `max_parallel_maintenance_workers` | 4 | 维护操作并行进程 |
| `max_worker_processes` | 16 | 最大工作进程总数 |

### WAL 和检查点优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `wal_buffers` | 64MB | WAL 缓冲区大小 |
| `wal_compression` | lz4 | WAL 压缩（减少 I/O） |
| `checkpoint_timeout` | 10min | 检查点间隔 |
| `checkpoint_completion_target` | 0.9 | 检查点平滑完成比例 |
| `max_wal_size` | 2GB | 最大 WAL 大小 |

### I/O 优化

| 参数 | 值 | 说明 |
|------|-----|------|
| `random_page_cost` | 1.1 | SSD 优化（鼓励索引扫描） |
| `effective_io_concurrency` | 200 | 有效 I/O 并发数（SSD 推荐） |
| `jit` | on | JIT 编译（复杂查询加速） |

---

## 高可用配置

### 流复制（主从复制）

PostgreSQL 已配置流复制支持参数：

```ini
wal_level = replica          # 支持流复制
max_wal_senders = 5          # 最大 WAL 发送进程
wal_keep_size = 1GB          # 保留 WAL 大小
```

#### 配置主从复制步骤

1. **主节点**：取消注释 `pg_hba.conf` 中的复制连接规则

```
host    replication     replication_user  172.16.0.0/12    scram-sha-256
```

2. **主节点**：创建复制用户

```sql
CREATE USER replication_user WITH REPLICATION PASSWORD 'replication_password';
```

3. **从节点**：使用 `pg_basebackup` 初始化

```bash
pg_basebackup -h <主节点IP> -p 55432 -U replication_user -D /opt/postgresql/data -Fp -Xs -P
```

### 备份策略

```bash
# 逻辑备份（推荐日常使用）
docker exec postgresql /opt/postgresql/bin/pg_dump -U postgres -h 127.0.0.1 -p 55432 myapp > backup.sql

# 全量物理备份
docker exec postgresql /opt/postgresql/bin/pg_basebackup \
    -h 127.0.0.1 -p 55432 -U postgres -D /tmp/backup -Fp -Xs -P

# 定时备份（crontab 示例）
# 0 2 * * * docker exec postgresql /opt/postgresql/bin/pg_dump -U postgres -h 127.0.0.1 -p 55432 myapp | gzip > /backup/myapp_$(date +\%Y\%m\%d).sql.gz
```

---

## 常见问题

### Q: 容器启动后立即退出

**A**: 检查日志 `docker logs postgresql`，常见原因：
1. PostgreSQL 配置语法错误
2. 文件权限不正确（数据目录必须是 700）
3. 端口被占用
4. 共享内存不足（检查 `shm_size` 设置）

### Q: PostgreSQL 连接被拒绝

**A**: 确保应用容器和 PostgreSQL 在同一 Docker 网络：
```bash
docker network ls
docker network inspect nginx-network
# 确认 PostgreSQL 容器在网络中
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432
```

### Q: 认证失败 (authentication failed)

**A**: 检查以下几点：
1. 确认设置了 `POSTGRES_PASSWORD` 环境变量
2. 确认使用 scram-sha-256 认证方式
3. 确认连接的用户名和密码正确
```bash
# 使用超级用户连接测试
docker exec -it postgresql /opt/postgresql/bin/psql -U postgres -h 127.0.0.1 -p 55432
```

### Q: 如何设置 PostgreSQL 密码

**A**: 在 `docker-compose.yml` 中设置环境变量：
```yaml
environment:
  POSTGRES_PASSWORD: "your_secure_password_here"
```

### Q: 如何查看 PostgreSQL 信息

```bash
# 查看版本
docker exec postgresql /opt/postgresql/bin/postgres --version

# 查看运行状态
docker exec postgresql /opt/postgresql/bin/pg_isready -h 127.0.0.1 -p 55432

# 查看配置
docker exec -it postgresql /opt/postgresql/bin/psql -U postgres -h 127.0.0.1 -p 55432 -c "SHOW ALL;"
```

### Q: 如何进入容器调试

```bash
docker exec -it postgresql /bin/bash
```

### Q: 如何连接到 PostgreSQL CLI

```bash
# 使用 psql（容器内）
docker exec -it postgresql /opt/postgresql/bin/psql -U postgres -h 127.0.0.1 -p 55432

# 连接特定数据库
docker exec -it postgresql /opt/postgresql/bin/psql -U myapp_user -h 127.0.0.1 -p 55432 -d myapp
```

### Q: 共享内存不足 (could not resize shared memory segment)

**A**: 增加 docker-compose.yml 中的 `shm_size`：
```yaml
shm_size: "1g"  # 默认 512m，可根据需要增加
```

### Q: 数据目录权限错误

**A**: PostgreSQL 要求数据目录权限必须是 700：
```bash
docker exec postgresql chmod 700 /opt/postgresql/data
```

### Q: 如何启用 SSL/TLS

**A**: 取消注释 `postgresql.conf` 中的 SSL 配置，并挂载证书：
```yaml
volumes:
  - ./ssl:/opt/postgresql/ssl:ro
```

## 许可证

本项目遵循 [MIT License](../LICENSE)。
