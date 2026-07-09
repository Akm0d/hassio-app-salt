#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly LOG_DIR="/srv/materium-dev/logs"
readonly PROXY_LOG="${LOG_DIR}/materium-proxy-supervisor.log"

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${PROXY_LOG}"
    exec > >(tee -a "${PROXY_LOG}") 2>&1
}

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/${MATERIUM_MASTER_RET_PORT}" >/dev/null 2>&1; do
        printf '[materium-proxy-supervisor] Waiting for salt-master before starting Docker proxy minions\n'
        sleep 2
    done
}

ensure_materium_source() {
    if [[ ! -f "${MATERIUM_APP_DIR}/pyproject.toml" ]]; then
        printf '[materium-proxy-supervisor] No Materium checkout found at %s\n' "${MATERIUM_APP_DIR}" >&2
        printf '[materium-proxy-supervisor] Run /home/akmod/code/sync-materium-to-ha.sh before starting the add-on, or package Materium into /opt/materium\n' >&2
        return 1
    fi
}

main() {
    setup_logging
    if [[ ! -f /run/materium-env ]]; then
        printf '[materium-proxy-supervisor] Missing /run/materium-env; init-salt did not complete\n' >&2
        return 1
    fi
    # shellcheck disable=SC1091
    source /run/materium-env
    wait_for_master
    ensure_materium_source
    printf '[materium-proxy-supervisor] Starting Docker proxy supervisor from %s\n' "${MATERIUM_APP_DIR}"
    cd "${MATERIUM_APP_DIR}"
    exec uv run --no-sync --extra test python /usr/bin/materium-proxy-supervisor.py
}

main "$@"
