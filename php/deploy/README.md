# PHP-FPM Docker 安全部署

基于 CIS Docker Benchmark 标准的 PHP-FPM 安全容器化部署方案。

> 此仓库提供 Docker 使用和部署教程。镜像由 GitHub Actions 自动构建。
> 编译构建源码请参阅：[mzwrt/copilot](https://github.com/mzwrt/copilot)

## 快速开始

```bash
# 1. 克隆本仓库
git clone <仓库地址>
cd <仓库名>

# 2. 修改 docker-compose.yml 中的 image 地址
# image: <你的用户名>/php-fpm:latest

# 3. 启动容器
docker compose up -d

# 4. 验证
docker exec php php -v
docker exec php php -m
```

## 详细教程

📖 完整的 Docker 使用教程请参阅 **[DOCKER-USAGE.md](DOCKER-USAGE.md)**，包括：

- 卷挂载说明
- PHP 配置文件结构
- 与 Nginx 集成
- PHP 扩展管理
- 日常运维（备份/恢复/更新）
- 常见问题

## 安全特性

| 安全层面 | 实现方式 | 效果 |
|---------|---------|------|
| 容器级防护 | 非 root + Capabilities 限制 | 最小权限原则 |
| 应用级防护 | disable_functions + expose_php=Off | 减少攻击面 |
| 运维级防护 | 健康检查 + 日志收集 + 资源限制 | 安全运维 |

## 文件结构

```
├── README.md                          # 本文件
├── DOCKER-USAGE.md                    # Docker 使用教程
└── docker-compose.yml                 # Docker Compose 部署文件
```

## 许可证

[MIT License](https://github.com/mzwrt/copilot/blob/main/LICENSE)
