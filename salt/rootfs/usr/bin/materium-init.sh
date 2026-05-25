#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly BASE_DIR="/data/materium"
readonly MASTER_CONFIG_DIR="${BASE_DIR}/master/etc/salt"
readonly MINION_CONFIG_DIR="${BASE_DIR}/minion/etc/salt"
readonly LOCAL_CONFIG_DIR="${BASE_DIR}/local/etc/salt"
readonly SALT_ROOT="${BASE_DIR}/master/srv/salt"
readonly PILLAR_ROOT="${BASE_DIR}/master/srv/pillar"
readonly SYNCED_APP_DIR="/srv/materium-dev/materium"
readonly INIT_LOCK_DIR="/run/materium-init.lock"
readonly INIT_READY_FILE="/run/materium-init.ready"

log_info() {
    printf '[materium-init] %s\n' "$*"
}

read_option() {
    local key="${1}"
    local default="${2}"

    python3 - "${key}" "${default}" <<'PY'
import json
import sys

key = sys.argv[1]
default = sys.argv[2]
try:
    with open("/data/options.json", encoding="utf-8") as rfh:
        options = json.load(rfh)
except FileNotFoundError:
    options = {}

value = options.get(key, default)
if isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}

acquire_init_lock() {
    while ! mkdir "${INIT_LOCK_DIR}" 2>/dev/null; do
        sleep 0.1
    done

    trap 'rmdir "${INIT_LOCK_DIR}" 2>/dev/null || true' EXIT
}

ensure_tree() {
    mkdir -p \
        "${MASTER_CONFIG_DIR}" \
        "${MINION_CONFIG_DIR}" \
        "${LOCAL_CONFIG_DIR}" \
        "${SALT_ROOT}" \
        "${PILLAR_ROOT}" \
        "${BASE_DIR}/master/pki" \
        "${BASE_DIR}/master/var/cache/salt/master" \
        "${BASE_DIR}/master/var/run/salt/master" \
        "${BASE_DIR}/minion/pki" \
        "${BASE_DIR}/minion/var/cache/salt/minion" \
        "${BASE_DIR}/minion/var/run/salt/minion" \
        "${BASE_DIR}/local/pki" \
        "${BASE_DIR}/local/var/cache/salt/minion" \
        "${BASE_DIR}/local/var/run/salt/minion"

    if [[ ! -e /srv/salt ]]; then
        mkdir -p /srv
        ln -s "${SALT_ROOT}" /srv/salt
    fi

    if [[ ! -e /srv/pillar ]]; then
        mkdir -p /srv
        ln -s "${PILLAR_ROOT}" /srv/pillar
    fi

    if [[ ! -f "${SALT_ROOT}/top.sls" ]]; then
        cat <<'EOF' >"${SALT_ROOT}/top.sls"
base: {}
EOF
    fi

    if [[ ! -f "${PILLAR_ROOT}/top.sls" ]]; then
        cat <<'EOF' >"${PILLAR_ROOT}/top.sls"
base: {}
EOF
    fi
}

write_master_config() {
    local auto_accept="${1}"
    local log_level="${2}"

    cat <<EOF >"${MASTER_CONFIG_DIR}/master"
interface: 0.0.0.0
publish_port: 4505
ret_port: 4506
transport: zeromq
user: root
auto_accept: ${auto_accept}
open_mode: False
root_dir: ${BASE_DIR}/master
pki_dir: ${BASE_DIR}/master/pki
cachedir: ${BASE_DIR}/master/var/cache/salt/master
sock_dir: ${BASE_DIR}/master/var/run/salt/master
pidfile: /run/salt-master.pid
log_file: /dev/stderr
log_level: ${log_level}
log_level_logfile: ${log_level}
state_events: True
fileserver_backend:
  - roots
file_roots:
  base:
    - ${SALT_ROOT}
pillar_roots:
  base:
    - ${PILLAR_ROOT}
gitfs_remotes: []
EOF
}

write_minion_config() {
    local log_level="${1}"

    cat <<EOF >"${MINION_CONFIG_DIR}/minion"
id: materium-local
master: 127.0.0.1
master_port: 4506
publish_port: 4505
ret_port: 4506
transport: zeromq
user: root
file_client: remote
saltenv: base
pillarenv: base
root_dir: ${BASE_DIR}/minion
pki_dir: ${BASE_DIR}/minion/pki
cachedir: ${BASE_DIR}/minion/var/cache/salt/minion
sock_dir: ${BASE_DIR}/minion/var/run/salt/minion
pidfile: /run/salt-minion.pid
log_file: /dev/stderr
log_level: ${log_level}
log_level_logfile: ${log_level}
EOF
}

write_local_config() {
    local log_level="${1}"

    cat <<EOF >"${LOCAL_CONFIG_DIR}/minion"
id: materium-master
master: 127.0.0.1
master_port: 4506
publish_port: 4505
ret_port: 4506
transport: zeromq
user: root
file_client: local
local: true
saltenv: base
pillarenv: base
root_dir: ${BASE_DIR}/local
pki_dir: ${BASE_DIR}/local/pki
cachedir: ${BASE_DIR}/local/var/cache/salt/minion
sock_dir: ${BASE_DIR}/local/var/run/salt/minion
log_file: /dev/stderr
log_level: ${log_level}
log_level_logfile: ${log_level}
file_roots:
  base:
    - ${SALT_ROOT}
pillar_roots:
  base:
    - ${PILLAR_ROOT}
EOF
}

write_environment() {
    local log_level="${1}"
    local app_dir="/opt/materium"
    local uv_project_environment="${MATERIUM_UV_PROJECT_ENVIRONMENT:-/opt/materium/.venv}"

    if [[ -f "${SYNCED_APP_DIR}/pyproject.toml" ]]; then
        app_dir="${SYNCED_APP_DIR}"
        uv_project_environment="${MATERIUM_UV_PROJECT_ENVIRONMENT:-${BASE_DIR}/dev-venv}"
    fi

    cat <<EOF >/run/materium-env
export MATERIUM_SALT_BASE_DIR=${BASE_DIR}
export MATERIUM_MASTER_CONFIG=${MASTER_CONFIG_DIR}/master
export MATERIUM_MINION_CONFIG=${MINION_CONFIG_DIR}/minion
export MATERIUM_LOCAL_MINION_CONFIG=${LOCAL_CONFIG_DIR}/minion
export MATERIUM_MANAGED_MINION_ID=materium-local
export MATERIUM_APP_DIR=${app_dir}
export MATERIUM_WEB_HOST=0.0.0.0
export MATERIUM_WEB_PORT=8099
export MATERIUM_LOG_LEVEL=${log_level}
export UV_PROJECT_ENVIRONMENT=${uv_project_environment}
export UV_LINK_MODE=copy
export UV_PYTHON=3.14
export UV_PYTHON_INSTALL_DIR=${UV_PYTHON_INSTALL_DIR:-/data/materium/uv-python}
export CC=clang
export CXX=clang++
EOF
}

main() {
    local log_level

    log_level="$(read_option 'log_level' 'info')"

    if [[ -f "${INIT_READY_FILE}" ]]; then
        write_environment "${log_level}"
        return 0
    fi

    acquire_init_lock

    if [[ -f "${INIT_READY_FILE}" ]]; then
        write_environment "${log_level}"
        return 0
    fi

    local auto_accept

    auto_accept="$(read_option 'auto_accept' 'true')"

    ensure_tree
    write_master_config "${auto_accept}" "${log_level}"
    write_minion_config "${log_level}"
    write_local_config "${log_level}"
    write_environment "${log_level}"

    touch "${INIT_READY_FILE}"
    log_info "Prepared Materium runtime under ${BASE_DIR}"
}

main "$@"
