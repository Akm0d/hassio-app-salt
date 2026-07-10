#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

export PYTHONPATH="/usr/lib${PYTHONPATH:+:${PYTHONPATH}}"

readonly LOG_DIR="/srv/salt-ha/logs"
readonly PROXY_LOG="${LOG_DIR}/salt-docker-proxy-supervisor.log"

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${PROXY_LOG}"
    exec > >(tee -a "${PROXY_LOG}") 2>&1
}

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/${SALT_HA_MASTER_RET_PORT}" >/dev/null 2>&1; do
        printf '[salt-docker-proxy-supervisor] Waiting for salt-master on return port %s\n' "${SALT_HA_MASTER_RET_PORT}"
        sleep 2
    done
}

main() {
    setup_logging
    if [[ ! -f /run/salt-ha-env ]]; then
        /usr/bin/salt-ha-init.sh
    fi
    # shellcheck disable=SC1091
    source /run/salt-ha-env
    wait_for_master
    exec python3 /usr/bin/salt-docker-proxy-supervisor.py
}

main "$@"
