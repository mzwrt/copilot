#!/bin/sh
# =======================================================
# PostgreSQL Docker 入口脚本
# 负责运行时初始化和权限检查
# =======================================================

set -e

PG_DIR="/opt/postgresql"
PGDATA="${PG_DIR}/data"

# 确保目录存在且可写
mkdir -p ${PG_DIR}/var/log 2>/dev/null || true
mkdir -p ${PG_DIR}/var/run 2>/dev/null || true
mkdir -p ${PGDATA} 2>/dev/null || true
mkdir -p ${PG_DIR}/wal 2>/dev/null || true

# 创建健康检查脚本
if [ ! -f /usr/local/bin/pg-healthcheck ]; then
    cat > /usr/local/bin/pg-healthcheck << 'HEALTHEOF'
#!/bin/sh
PG_DIR="/opt/postgresql"
${PG_DIR}/bin/pg_isready -h 127.0.0.1 -p 55432 -U postgres -q
HEALTHEOF
    chmod 555 /usr/local/bin/pg-healthcheck
fi

# 初始化数据库（仅首次运行时执行）
if [ ! -f "${PGDATA}/PG_VERSION" ]; then
    echo "Initializing PostgreSQL database..."

    # 确保目录权限正确（PostgreSQL 要求 700）
    chown postgres:postgres ${PGDATA}
    chmod 700 ${PGDATA}
    chown postgres:postgres ${PG_DIR}/wal
    chmod 700 ${PG_DIR}/wal

    # CIS - 使用数据校验和初始化（数据完整性保护）
    gosu postgres ${PG_DIR}/bin/initdb \
        --pgdata="${PGDATA}" \
        --auth=scram-sha-256 \
        --auth-local=peer \
        --encoding=UTF8 \
        --locale=en_US.UTF-8 \
        --data-checksums \
        --waldir="${PG_DIR}/wal" \
        --username=postgres

    # 复制安全加固配置文件到数据目录
    cp ${PG_DIR}/etc/postgresql.conf ${PGDATA}/postgresql.conf
    cp ${PG_DIR}/etc/pg_hba.conf ${PGDATA}/pg_hba.conf
    chown postgres:postgres ${PGDATA}/postgresql.conf ${PGDATA}/pg_hba.conf

    # 设置 PostgreSQL 超级用户密码
    if [ -n "${POSTGRES_PASSWORD}" ]; then
        gosu postgres ${PG_DIR}/bin/pg_ctl -D "${PGDATA}" -o "-c listen_addresses=''" -w start
        gosu postgres ${PG_DIR}/bin/psql -U postgres -c "ALTER USER postgres WITH PASSWORD '${POSTGRES_PASSWORD}';"
        echo "PostgreSQL superuser password configured from environment variable"

        # 创建应用数据库和用户（如果指定）
        if [ -n "${POSTGRES_DB}" ] && [ "${POSTGRES_DB}" != "postgres" ]; then
            gosu postgres ${PG_DIR}/bin/psql -U postgres -c "CREATE DATABASE \"${POSTGRES_DB}\";"
            echo "Database '${POSTGRES_DB}' created"
        fi

        if [ -n "${POSTGRES_USER}" ] && [ "${POSTGRES_USER}" != "postgres" ]; then
            gosu postgres ${PG_DIR}/bin/psql -U postgres -c "CREATE USER \"${POSTGRES_USER}\" WITH PASSWORD '${POSTGRES_PASSWORD}';"
            if [ -n "${POSTGRES_DB}" ]; then
                gosu postgres ${PG_DIR}/bin/psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE \"${POSTGRES_DB}\" TO \"${POSTGRES_USER}\";"
                gosu postgres ${PG_DIR}/bin/psql -U postgres -d "${POSTGRES_DB}" -c "GRANT ALL ON SCHEMA public TO \"${POSTGRES_USER}\";"
            fi
            echo "User '${POSTGRES_USER}' created and granted privileges"
        fi

        gosu postgres ${PG_DIR}/bin/pg_ctl -D "${PGDATA}" -m fast -w stop
    else
        echo "WARNING: POSTGRES_PASSWORD is not set. Using peer authentication only."
    fi

    echo "PostgreSQL initialization complete"
fi

# 确保配置文件是最新的（从 etc 目录同步到数据目录）
if [ -f "${PG_DIR}/etc/postgresql.conf" ]; then
    cp ${PG_DIR}/etc/postgresql.conf ${PGDATA}/postgresql.conf
    chown postgres:postgres ${PGDATA}/postgresql.conf
fi
if [ -f "${PG_DIR}/etc/pg_hba.conf" ]; then
    cp ${PG_DIR}/etc/pg_hba.conf ${PGDATA}/pg_hba.conf
    chown postgres:postgres ${PGDATA}/pg_hba.conf
fi

# 以 postgres 用户执行主命令
exec gosu postgres "$@"
