#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly LOG_DIR="/srv/materium-dev/logs"
readonly MINION_LOG="${LOG_DIR}/salt-minion.log"

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${MINION_LOG}"
    exec > >(tee -a "${MINION_LOG}") 2>&1
}

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/${MATERIUM_MASTER_RET_PORT}" >/dev/null 2>&1; do
        printf '[salt-minion] Waiting for salt-master to accept connections on %s\n' "${MATERIUM_MASTER_RET_PORT}"
        sleep 2
    done
}

main() {
    setup_logging
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
