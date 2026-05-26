#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        printf '[materium-worker] Waiting for salt-master before starting Materium worker\n'
        sleep 2
    done
}

ensure_materium_source() {
    if [[ ! -f "${MATERIUM_APP_DIR}/pyproject.toml" ]]; then
        printf '[materium-worker] No Materium checkout found at %s\n' "${MATERIUM_APP_DIR}" >&2
        printf '[materium-worker] Run /home/akmod/code/sync-materium-to-ha.sh before starting the add-on, or package Materium into /opt/materium\n' >&2
        return 1
    fi
}

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    wait_for_master
    ensure_materium_source
    printf '[materium-worker] Starting Materium worker from %s\n' "${MATERIUM_APP_DIR}"
    cd "${MATERIUM_APP_DIR}"
    exec uv run --extra test python -m hub -c "${MATERIUM_CONFIG}" prima.init.worker
}

main "$@"
