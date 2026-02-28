# PHP-FPM Docker 容器安全验证测试

## 概述

本目录包含 PHP-FPM Docker 容器的安全配置验证脚本，用于验证容器是否符合 CIS Docker Benchmark 安全基准。

## 测试项目

### 容器安全测试
- 容器运行状态检查
- 非特权模式运行 (CIS 5.4)
- no-new-privileges 安全选项 (CIS 5.25)
- cap_drop ALL (CIS 5.3)
- 内存限制 (CIS 5.10)
- CPU 限制 (CIS 5.11)
- PID 限制 (CIS 5.28)
- 健康检查配置 (CIS 5.26)
- 日志驱动配置

### PHP-FPM 服务测试
- PHP-FPM 进程运行状态
- 端口 9000 监听状态
- PHP 版本信息
- expose_php 安全配置
- disable_functions 安全限制
- allow_url_include 安全配置
- OPcache 性能优化状态
- PHP 扩展加载状态

### 文件权限测试
- 配置文件读取权限
- 日志目录权限
- Session 目录权限

## 使用方法

```bash
# 验证默认容器 (php)
bash validate.sh

# 验证指定容器
bash validate.sh my-php-container
```

## 测试结果

- `[PASS]` - 测试通过
- `[FAIL]` - 测试失败，需要修复
- `[SKIP]` - 测试跳过（条件不满足）
- `[INFO]` - 提示信息
