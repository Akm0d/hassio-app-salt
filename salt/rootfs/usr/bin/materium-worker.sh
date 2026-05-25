#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        printf '[materium-worker] Waiting for salt-master before starting Materium worker\n'
        sleep 2
    done
}

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    wait_for_master
    printf '[materium-worker] Starting Materium worker from %s\n' "${MATERIUM_APP_DIR}"
    cd "${MATERIUM_APP_DIR}"
    exec uv run --extra test python -m hub prima.init.worker
}

main "$@"
