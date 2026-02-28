# Nginx Docker 安全部署方案

基于 CIS Docker Benchmark、CIS Nginx Benchmark 和 PCI DSS v4.0 标准的 Nginx 安全容器化部署方案。

## 快速开始

所有 Nginx 相关文件和安全配置位于 [`nginx/`](nginx/) 目录中，详细文档请参阅 [`nginx/README.md`](nginx/README.md)。

```bash
# 构建镜像
cd nginx
docker compose build

# 启动容器
docker compose up -d

# 运行安全检查
bash security/cis-docker-benchmark/docker-bench-check.sh

# 运行验证测试
bash tests/validate.sh
```

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
nginx/
├── Dockerfile                         # 多阶段 Docker 构建文件
├── docker-compose.yml                 # Docker Compose 安全配置
├── docker-entrypoint.sh               # 容器入口脚本
├── nginx-install.sh                   # 原始裸机安装脚本（参考）
├── .dockerignore                      # 构建上下文排除规则
├── README.md                          # 主文档
├── security/                          # 安全配置
│   ├── seccomp/                       # Seccomp 系统调用限制
│   ├── apparmor/                      # AppArmor 访问控制
│   ├── secrets/                       # Docker Secrets 管理
│   ├── audit/                         # 审计日志配置
│   ├── cis-docker-benchmark/          # CIS Docker 基准检查
│   ├── cis-nginx-benchmark/           # CIS Nginx 基准配置
│   ├── pci-dss/                       # PCI DSS 合规
│   └── performance/                   # 性能调优
└── tests/                             # 验证与测试
```