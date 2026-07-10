#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly LOG_DIR="/srv/salt-ha/logs"
readonly MASTER_LOG="${LOG_DIR}/salt-master.log"

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${MASTER_LOG}"
    exec > >(tee -a "${MASTER_LOG}") 2>&1
}

main() {
    setup_logging
    /usr/bin/salt-ha-init.sh
    # shellcheck disable=SC1091
    source /run/salt-ha-env
    printf '[salt-master] Starting salt-master with config %s\n' "${SALT_HA_MASTER_CONFIG_DIR}"
    exec salt-master \
        -c "${SALT_HA_MASTER_CONFIG_DIR}" \
        --log-file=/dev/stderr
}
main "$@"
