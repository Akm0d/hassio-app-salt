#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/${MATERIUM_MASTER_RET_PORT}" >/dev/null 2>&1; do
        printf '[salt-minion] Waiting for salt-master to accept connections on %s\n' "${MATERIUM_MASTER_RET_PORT}"
        sleep 2
    done
}

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    wait_for_master
    printf '[salt-minion] Starting local salt-minion with config %s\n' "$(dirname "${MATERIUM_MINION_CONFIG}")"
    exec salt-minion \
        -c "$(dirname "${MATERIUM_MINION_CONFIG}")" \
        --log-file=/dev/stderr
}

main "$@"
