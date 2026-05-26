#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        printf '[materium-web] Waiting for salt-master before starting Materium web\n'
        sleep 2
    done
}

ensure_materium_source() {
    if [[ ! -f "${MATERIUM_APP_DIR}/pyproject.toml" ]]; then
        printf '[materium-web] No Materium checkout found at %s\n' "${MATERIUM_APP_DIR}" >&2
        printf '[materium-web] Run /home/akmod/code/sync-materium-to-ha.sh before starting the add-on, or package Materium into /opt/materium\n' >&2
        return 1
    fi
}

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    wait_for_master
    ensure_materium_source
    printf '[materium-web] Starting Materium web from %s on 0.0.0.0:8099\n' "${MATERIUM_APP_DIR}"
    cd "${MATERIUM_APP_DIR}"
    if [[ "${MATERIUM_WEB_DEBUGPY:-}" == "1" ]]; then
        debug_port="${MATERIUM_WEB_DEBUGPY_PORT:-5678}"
        printf '[materium-web] Starting debugpy on 0.0.0.0:%s\n' "${debug_port}"
        exec uv run --with=debugpy --extra test python -m debugpy --listen "0.0.0.0:${debug_port}" -m hub -c "${MATERIUM_CONFIG}" prima.init.web
    fi
    exec uv run --extra test python -m hub -c "${MATERIUM_CONFIG}" prima.init.web
}

main "$@"
