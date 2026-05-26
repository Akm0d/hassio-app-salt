#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly DATA_DIR="/data/materium"
readonly SYNCED_APP_DIR="/srv/materium-dev/materium"
readonly INIT_LOCK_DIR="/run/materium-init.lock"
readonly INIT_READY_FILE="/run/materium-init.ready"

SALT_BASE_DIR=""
MASTER_CONFIG_DIR=""
MINION_CONFIG_DIR=""
LOCAL_CONFIG_DIR=""
SALT_ROOT=""
PILLAR_ROOT=""
MATERIUM_CONFIG=""

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
legacy = {"master.log_level": "log_level", "master.auto_accept": "auto_accept"}
try:
    with open("/data/options.json", encoding="utf-8") as rfh:
        options = json.load(rfh)
except FileNotFoundError:
    options = {}

value = options
for part in key.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        value = None
        break

if value is None and key in legacy:
    value = options.get(legacy[key])
if value is None:
    value = default

if isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}

configure_paths() {
    SALT_BASE_DIR="${1}"
    MASTER_CONFIG_DIR="${SALT_BASE_DIR}/master/etc/salt"
    MINION_CONFIG_DIR="${SALT_BASE_DIR}/minion/etc/salt"
    LOCAL_CONFIG_DIR="${SALT_BASE_DIR}/local/etc/salt"
    SALT_ROOT="${SALT_BASE_DIR}/master/srv/salt"
    PILLAR_ROOT="${SALT_BASE_DIR}/master/srv/pillar"
    MATERIUM_CONFIG="${DATA_DIR}/materium.yaml"
}

acquire_init_lock() {
    while ! mkdir "${INIT_LOCK_DIR}" 2>/dev/null; do
        sleep 0.1
    done

    trap 'rmdir "${INIT_LOCK_DIR}" 2>/dev/null || true' EXIT
}

ensure_tree() {
    mkdir -p \
        "${DATA_DIR}" \
        "${MASTER_CONFIG_DIR}" \
        "${MINION_CONFIG_DIR}" \
        "${LOCAL_CONFIG_DIR}" \
        "${SALT_ROOT}" \
        "${PILLAR_ROOT}" \
        "${SALT_BASE_DIR}/master/pki" \
        "${SALT_BASE_DIR}/master/var/cache/salt/master" \
        "${SALT_BASE_DIR}/master/var/run/salt/master" \
        "${SALT_BASE_DIR}/minion/pki" \
        "${SALT_BASE_DIR}/minion/var/cache/salt/minion" \
        "${SALT_BASE_DIR}/minion/var/run/salt/minion" \
        "${SALT_BASE_DIR}/local/pki" \
        "${SALT_BASE_DIR}/local/var/cache/salt/minion" \
        "${SALT_BASE_DIR}/local/var/run/salt/minion"

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
root_dir: ${SALT_BASE_DIR}/master
pki_dir: ${SALT_BASE_DIR}/master/pki
cachedir: ${SALT_BASE_DIR}/master/var/cache/salt/master
sock_dir: ${SALT_BASE_DIR}/master/var/run/salt/master
pidfile: /run/salt-master.pid
log_file: /dev/stderr
log_level: ${log_level}
log_level_logfile: ${log_level}
state_events: True
fileserver_backend:
  - git
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
    local master="${2}"

    cat <<EOF >"${MINION_CONFIG_DIR}/minion"
id: materium-local
master: ${master}
master_port: 4506
publish_port: 4505
ret_port: 4506
transport: zeromq
user: root
file_client: remote
saltenv: base
pillarenv: base
root_dir: ${SALT_BASE_DIR}/minion
pki_dir: ${SALT_BASE_DIR}/minion/pki
cachedir: ${SALT_BASE_DIR}/minion/var/cache/salt/minion
sock_dir: ${SALT_BASE_DIR}/minion/var/run/salt/minion
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
root_dir: ${SALT_BASE_DIR}/local
pki_dir: ${SALT_BASE_DIR}/local/pki
cachedir: ${SALT_BASE_DIR}/local/var/cache/salt/minion
sock_dir: ${SALT_BASE_DIR}/local/var/run/salt/minion
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

write_materium_config() {
    local web_host="${1}"
    local web_port="${2}"
    local cache_db="${3}"
    local master_log_level="${4}"
    local auto_accept="${5}"
    local minion_log_level="${6}"
    local minion_master="${7}"

    cat <<EOF >"${MATERIUM_CONFIG}"
config:
  materium:
    host: ${web_host}
    port: ${web_port}
    cache_db: ${cache_db}
    base_dir: ${SALT_BASE_DIR}
  master:
    log_level: ${master_log_level}
    auto_accept: ${auto_accept}
    fileserver_backend:
      - git
      - roots
    external_auth:
      auto:
        '*':
          - '*'
          - '@wheel'
          - '@runner'
  minion:
    file_client: local
    log_level: ${minion_log_level}
    master: ${minion_master}
EOF
}

write_environment() {
    local log_level="${1}"
    local web_host="${2}"
    local web_port="${3}"
    local app_dir="/opt/materium"
    local uv_project_environment="${MATERIUM_UV_PROJECT_ENVIRONMENT:-/opt/materium/.venv}"

    if [[ -f "${SYNCED_APP_DIR}/pyproject.toml" ]]; then
        app_dir="${SYNCED_APP_DIR}"
        uv_project_environment="${MATERIUM_UV_PROJECT_ENVIRONMENT:-${DATA_DIR}/dev-venv}"
    fi

    cat <<EOF >/run/materium-env
export MATERIUM_BASE_DIR=${SALT_BASE_DIR}
export MATERIUM_SALT_BASE_DIR=${SALT_BASE_DIR}
export MATERIUM_CONFIG=${MATERIUM_CONFIG}
export MATERIUM_MASTER_CONFIG=${MASTER_CONFIG_DIR}/master
export MATERIUM_MINION_CONFIG=${MINION_CONFIG_DIR}/minion
export MATERIUM_LOCAL_MINION_CONFIG=${LOCAL_CONFIG_DIR}/minion
export MATERIUM_MANAGED_MINION_ID=materium-local
export MATERIUM_APP_DIR=${app_dir}
export MATERIUM_WEB_HOST=${web_host}
export MATERIUM_WEB_PORT=${web_port}
export MATERIUM_LOG_LEVEL=${log_level}
export UV_PROJECT_ENVIRONMENT=${uv_project_environment}
export UV_LINK_MODE=copy
export UV_PYTHON=3.14
export UV_PYTHON_INSTALL_DIR=${UV_PYTHON_INSTALL_DIR:-${DATA_DIR}/uv-python}
export CC=clang
export CXX=clang++
EOF
}

main() {
    local auto_accept
    local cache_db
    local master_log_level
    local minion_log_level
    local minion_master
    local salt_base_dir
    local web_host
    local web_port

    salt_base_dir="$(read_option 'materium.base_dir' '/data/materium/salt')"
    web_host="$(read_option 'materium.host' '0.0.0.0')"
    web_port="$(read_option 'materium.port' '8099')"
    cache_db="$(read_option 'materium.cache_db' '/data/materium/cache.sqlite')"
    master_log_level="$(read_option 'master.log_level' 'info')"
    auto_accept="$(read_option 'master.auto_accept' 'false')"
    minion_log_level="$(read_option 'minion.log_level' "${master_log_level}")"
    minion_master="$(read_option 'minion.master' '127.0.0.1')"

    configure_paths "${salt_base_dir}"

    acquire_init_lock

    ensure_tree
    write_master_config "${auto_accept}" "${master_log_level}"
    write_minion_config "${minion_log_level}" "${minion_master}"
    write_local_config "${minion_log_level}"
    write_materium_config "${web_host}" "${web_port}" "${cache_db}" "${master_log_level}" "${auto_accept}" "${minion_log_level}" "${minion_master}"
    write_environment "${master_log_level}" "${web_host}" "${web_port}"

    touch "${INIT_READY_FILE}"
    log_info "Prepared Materium runtime under ${SALT_BASE_DIR}"
}

main "$@"
