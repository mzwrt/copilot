#!/usr/bin/env bash
# =======================================================
# Redis Docker 容器安全配置验证脚本
# 验证 CIS Docker Benchmark 合规性
# =======================================================
#
# 用法：
#   ./validate.sh [容器名称]
#
# 参数：
#   容器名称  - 要验证的 Docker 容器名称（默认: redis）
#
# 示例：
#   ./validate.sh
#   ./validate.sh my-redis
#

set -euo pipefail

# ============================================================
# 全局变量
# ============================================================

# 容器名称，默认为 "redis"
CONTAINER_NAME="${1:-redis}"

# Redis 安装目录
REDIS_DIR="/opt/redis"

# 测试计数器
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
INFO_COUNT=0
TOTAL_COUNT=0

# ============================================================
# 颜色定义
# ============================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    BOLD=''
    NC=''
fi

# ============================================================
# 辅助函数
# ============================================================

pass() {
    ((TOTAL_COUNT++)) || true
    ((PASS_COUNT++)) || true
    echo -e "${GREEN}[PASS]${NC} $1"
}

fail() {
    ((TOTAL_COUNT++)) || true
    ((FAIL_COUNT++)) || true
    echo -e "${RED}[FAIL]${NC} $1"
}

skip() {
    ((TOTAL_COUNT++)) || true
    ((SKIP_COUNT++)) || true
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

info() {
    ((INFO_COUNT++)) || true
    echo -e "${BLUE}[INFO]${NC} $1"
}

docker_exec() {
    docker exec "${CONTAINER_NAME}" "$@" 2>/dev/null
}

get_inspect() {
    if [[ -z "${INSPECT_CACHE:-}" ]]; then
        INSPECT_CACHE=$(docker inspect "${CONTAINER_NAME}" 2>/dev/null) || INSPECT_CACHE=""
    fi
    echo "${INSPECT_CACHE}"
}

section() {
    echo ""
    echo -e "${BOLD}=== $1 ===${NC}"
    echo ""
}

# ============================================================
# 容器安全测试
# ============================================================
test_container() {
    section "容器安全测试 (Container Security Tests)"

    local inspect
    inspect=$(get_inspect)

    # 检查容器是否正在运行
    local state
    state=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['State']['Status'])" 2>/dev/null) || state=""
    if [[ "${state}" == "running" ]]; then
        pass "容器 '${CONTAINER_NAME}' 正在运行"
    else
        fail "容器 '${CONTAINER_NAME}' 未运行 (状态: ${state:-unknown})"
        info "后续测试可能会失败，请先启动容器"
        return
    fi

    # 检查容器是否以非特权模式运行 (CIS 5.4)
    local privileged
    privileged=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['Privileged'])" 2>/dev/null) || privileged=""
    if [[ "${privileged}" == "False" ]]; then
        pass "容器未以特权模式运行 (CIS 5.4)"
    else
        fail "容器以特权模式运行 (CIS 5.4)"
    fi

    # 检查 no-new-privileges 安全选项 (CIS 5.25)
    local security_opts
    security_opts=$(echo "${inspect}" | python3 -c "import sys,json; opts=json.load(sys.stdin)[0]['HostConfig']['SecurityOpt']; print(' '.join(opts) if opts else '')" 2>/dev/null) || security_opts=""
    if echo "${security_opts}" | grep -q "no-new-privileges"; then
        pass "已启用 no-new-privileges 安全选项 (CIS 5.25)"
    else
        fail "未启用 no-new-privileges 安全选项 (CIS 5.25)"
    fi

    # 检查 cap_drop ALL (CIS 5.3)
    local cap_drop
    cap_drop=$(echo "${inspect}" | python3 -c "import sys,json; caps=json.load(sys.stdin)[0]['HostConfig']['CapDrop']; print(' '.join(caps) if caps else '')" 2>/dev/null) || cap_drop=""
    if echo "${cap_drop}" | grep -qi "all"; then
        pass "已配置 cap_drop ALL (CIS 5.3)"
    else
        fail "未配置 cap_drop ALL (CIS 5.3)"
    fi

    # 检查内存限制 (CIS 5.10)
    local memory
    memory=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['Memory'])" 2>/dev/null) || memory="0"
    if [[ "${memory}" -gt 0 ]]; then
        local memory_mb=$((memory / 1024 / 1024))
        pass "已设置内存限制: ${memory_mb}MB (CIS 5.10)"
    else
        fail "未设置内存限制 (CIS 5.10)"
    fi

    # 检查 CPU 限制 (CIS 5.11)
    local nano_cpus cpu_period cpu_quota
    nano_cpus=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['NanoCpus'])" 2>/dev/null) || nano_cpus="0"
    cpu_period=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['CpuPeriod'])" 2>/dev/null) || cpu_period="0"
    cpu_quota=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['CpuQuota'])" 2>/dev/null) || cpu_quota="0"
    if [[ "${nano_cpus}" -gt 0 ]] || { [[ "${cpu_period}" -gt 0 ]] && [[ "${cpu_quota}" -gt 0 ]]; }; then
        pass "已设置 CPU 限制 (CIS 5.11)"
    else
        fail "未设置 CPU 限制 (CIS 5.11)"
    fi

    # 检查 PID 限制 (CIS 5.28)
    local pids_limit
    pids_limit=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['PidsLimit'])" 2>/dev/null) || pids_limit="0"
    if [[ "${pids_limit}" -gt 0 ]]; then
        pass "已设置 PID 限制: ${pids_limit} (CIS 5.28)"
    else
        fail "未设置 PID 限制 (CIS 5.28)"
    fi

    # 检查健康检查配置 (CIS 5.26)
    local healthcheck
    healthcheck=$(echo "${inspect}" | python3 -c "import sys,json; hc=json.load(sys.stdin)[0]['Config'].get('Healthcheck'); print(hc['Test'] if hc else '')" 2>/dev/null) || healthcheck=""
    if [[ -n "${healthcheck}" ]]; then
        pass "已配置健康检查 (CIS 5.26)"
    else
        fail "未配置健康检查 (CIS 5.26)"
    fi

    # 检查日志驱动配置
    local log_driver
    log_driver=$(echo "${inspect}" | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['HostConfig']['LogConfig']['Type'])" 2>/dev/null) || log_driver=""
    if [[ -n "${log_driver}" ]]; then
        pass "已配置日志驱动: ${log_driver}"
    else
        fail "未配置日志驱动"
    fi
}

# ============================================================
# Redis 服务测试
# ============================================================
test_redis() {
    section "Redis 服务测试 (Redis Service Tests)"

    # 检查 Redis 进程是否正在运行
    local redis_pid
    redis_pid=$(docker_exec pgrep -x redis-server) || redis_pid=""
    if [[ -n "${redis_pid}" ]]; then
        pass "Redis 进程正在运行"
    else
        fail "Redis 进程未运行"
        info "后续 Redis 测试将被跳过"
        return
    fi

    # 检查 Redis 是否在 36379 端口监听
    local port_listen
    port_listen=$(docker_exec sh -c "ss -tlnp 2>/dev/null | grep ':36379' || netstat -tlnp 2>/dev/null | grep ':36379'") || port_listen=""
    if [[ -n "${port_listen}" ]]; then
        pass "Redis 在端口 36379 正常监听"
    else
        local redis_conf_port
        redis_conf_port=$(docker_exec grep "^port" "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || redis_conf_port=""
        if [[ -n "${redis_conf_port}" ]]; then
            info "Redis 端口配置: ${redis_conf_port}"
        else
            fail "Redis 端口 36379 未监听"
        fi
    fi

    # 检查 Redis 版本信息
    local redis_version
    redis_version=$(docker_exec ${REDIS_DIR}/bin/redis-server --version 2>/dev/null) || redis_version=""
    if [[ -n "${redis_version}" ]]; then
        pass "Redis 版本: ${redis_version}"
    else
        fail "无法获取 Redis 版本信息"
    fi

    # 检查密码认证是否配置
    local requirepass
    requirepass=$(docker_exec grep "^requirepass" "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || requirepass=""
    if [[ -n "${requirepass}" ]]; then
        pass "已配置密码认证 (requirepass)"
    else
        info "未配置密码认证（REDIS_PASSWORD 环境变量未设置）"
    fi

    # 检查 protected-mode 是否启用
    local protected_mode
    protected_mode=$(docker_exec grep "^protected-mode" "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || protected_mode=""
    if echo "${protected_mode}" | grep -q "yes"; then
        pass "protected-mode 已启用（安全）"
    elif [[ -n "${protected_mode}" ]]; then
        fail "protected-mode 未启用: ${protected_mode}"
    else
        skip "无法检查 protected-mode 配置"
    fi

    # 检查危险命令是否已重命名
    local renamed_flushdb renamed_flushall renamed_debug
    renamed_flushdb=$(docker_exec grep 'rename-command FLUSHDB' "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || renamed_flushdb=""
    renamed_flushall=$(docker_exec grep 'rename-command FLUSHALL' "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || renamed_flushall=""
    renamed_debug=$(docker_exec grep 'rename-command DEBUG' "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || renamed_debug=""
    if [[ -n "${renamed_flushdb}" ]] && [[ -n "${renamed_flushall}" ]] && [[ -n "${renamed_debug}" ]]; then
        pass "危险命令已重命名/禁用 (FLUSHDB, FLUSHALL, DEBUG)"
    else
        fail "部分危险命令未重命名"
    fi

    # 检查 maxmemory 是否配置
    local maxmemory
    maxmemory=$(docker_exec grep "^maxmemory " "${REDIS_DIR}/etc/redis.conf" 2>/dev/null) || maxmemory=""
    if [[ -n "${maxmemory}" ]]; then
        pass "已配置内存限制: ${maxmemory}"
    else
        fail "未配置 maxmemory（安全风险）"
    fi
}

# ============================================================
# 文件权限测试
# ============================================================
test_file_permissions() {
    section "文件权限测试 (File Permission Tests)"

    # 检查配置文件是否不可被其他用户读取
    local conf_world_readable
    conf_world_readable=$(docker_exec find "${REDIS_DIR}/etc" -type f -perm -o=r 2>/dev/null) || conf_world_readable=""
    if [[ -z "${conf_world_readable}" ]]; then
        pass "配置文件不可被其他用户读取 (CIS)"
    else
        local count
        count=$(echo "${conf_world_readable}" | wc -l)
        fail "发现 ${count} 个配置文件可被其他用户读取 (CIS)"
    fi

    # 检查日志目录权限
    local log_dir_perms
    log_dir_perms=$(docker_exec stat -c '%a' "${REDIS_DIR}/var/log" 2>/dev/null) || log_dir_perms=""
    if [[ -n "${log_dir_perms}" ]]; then
        if [[ $((8#${log_dir_perms})) -le $((8#750)) ]]; then
            pass "日志目录权限正确: ${log_dir_perms}"
        else
            fail "日志目录权限过宽: ${log_dir_perms}，应为 750 或更严格"
        fi
    else
        skip "日志目录不存在，跳过权限检查"
    fi

    # 检查数据目录权限
    local data_dir_perms
    data_dir_perms=$(docker_exec stat -c '%a' "${REDIS_DIR}/data" 2>/dev/null) || data_dir_perms=""
    if [[ -n "${data_dir_perms}" ]]; then
        if [[ $((8#${data_dir_perms})) -le $((8#750)) ]]; then
            pass "数据目录权限正确: ${data_dir_perms}"
        else
            fail "数据目录权限过宽: ${data_dir_perms}，应为 750 或更严格"
        fi
    else
        skip "数据目录不存在，跳过权限检查"
    fi
}

# ============================================================
# 打印测试摘要
# ============================================================
print_summary() {
    section "测试摘要 (Test Summary)"

    echo -e "  容器名称:  ${BOLD}${CONTAINER_NAME}${NC}"
    echo -e "  测试总数:  ${BOLD}${TOTAL_COUNT}${NC}"
    echo -e "  ${GREEN}通过: ${PASS_COUNT}${NC}"
    echo -e "  ${RED}失败: ${FAIL_COUNT}${NC}"
    echo -e "  ${YELLOW}跳过: ${SKIP_COUNT}${NC}"
    echo -e "  ${BLUE}提示: ${INFO_COUNT}${NC}"
    echo ""

    if [[ ${FAIL_COUNT} -eq 0 ]]; then
        echo -e "${GREEN}${BOLD}所有测试通过！容器安全配置符合要求。${NC}"
    else
        echo -e "${RED}${BOLD}存在 ${FAIL_COUNT} 项测试失败，请检查并修复安全配置。${NC}"
    fi
    echo ""
}

# ============================================================
# 主函数
# ============================================================
main() {
    echo ""
    echo -e "${BOLD}Redis Docker 容器安全配置验证${NC}"
    echo -e "目标容器: ${BOLD}${CONTAINER_NAME}${NC}"
    echo -e "验证时间: $(date '+%Y-%m-%d %H:%M:%S')"

    # 预检查：确认 Docker 和 python3 是否可用
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}错误: docker 命令不可用，请先安装 Docker${NC}"
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}错误: python3 命令不可用，请先安装 Python 3${NC}"
        exit 1
    fi

    # 预检查：确认容器是否存在
    if ! docker inspect "${CONTAINER_NAME}" &>/dev/null; then
        echo -e "${RED}错误: 容器 '${CONTAINER_NAME}' 不存在${NC}"
        echo -e "用法: $0 [容器名称]"
        exit 1
    fi

    # 执行各类测试
    test_container
    test_redis
    test_file_permissions

    # 打印测试摘要
    print_summary

    # 返回状态码：有失败则返回 1
    if [[ ${FAIL_COUNT} -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

# 运行主函数
main
