#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly DATA_DIR="/data/materium"
readonly SYNCED_APP_DIR="/srv/materium-dev/materium"
readonly INIT_LOCK_DIR="/run/materium-init.lock"
readonly INIT_READY_FILE="/run/materium-init.ready"

MATERIUM_CONFIG=""

log_info() {
    printf '[materium-init] %s\n' "$*"
}


acquire_init_lock() {
    while ! mkdir "${INIT_LOCK_DIR}" 2>/dev/null; do
        sleep 0.1
    done

    trap 'rmdir "${INIT_LOCK_DIR}" 2>/dev/null || true' EXIT
}

main() {

    local materium_config
    local master_config
    local minion_config
    local app_dir="/opt/materium"
    local uv_project_environment="/opt/materium/.venv"

    MATERIUM_CONFIG="${DATA_DIR}/materium.yaml"
    log_info "Starting materium init"

    acquire_init_lock

    if [[ -f "${SYNCED_APP_DIR}/pyproject.toml" ]]; then
        log_info "Using development app from ${SYNCED_APP_DIR}"
        app_dir="${SYNCED_APP_DIR}"
        uv_project_environment="${DATA_DIR}/dev-venv"
    else
        log_info "Using production app from ${app_dir}"
    fi

    log_info "Writing environment variables to /run/materium-env"
    cat <<EOF >/run/materium-env
export UV_PROJECT_ENVIRONMENT=${uv_project_environment}
export UV_LINK_MODE=copy
export UV_PYTHON=3.14
export UV_PYTHON_INSTALL_DIR=${UV_PYTHON_INSTALL_DIR:-${DATA_DIR}/uv-python}
export CC=clang
export CXX=clang++
EOF

    log_info "Writing materium configuration to ${MATERIUM_CONFIG}"
    jq '{materium: (.materium + {port: .ingress_port}), master: (.master + {publish_port: .ports["4505/tcp"], ret_port: .ports["4506/tcp"]}), minion}' /data/options.json | yq -P '.' > "${MATERIUM_CONFIG}"

    log_info "App ready, releasing init lock and signaling readiness"
    touch "${INIT_READY_FILE}"
}

main "$@"
