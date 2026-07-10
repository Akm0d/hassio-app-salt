#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

export PYTHONPATH="/usr/lib${PYTHONPATH:+:${PYTHONPATH}}"

readonly LOG_DIR="/srv/salt-ha/logs"
readonly INIT_LOG="${LOG_DIR}/salt-ha-init.log"

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${INIT_LOG}"
    exec > >(tee -a "${INIT_LOG}") 2>&1
}

main() {
    setup_logging
    printf '[salt-ha-init] Writing Salt add-on runtime configuration\n'
    python3 -m salt_ha.runtime
    printf '[salt-ha-init] Runtime configuration ready\n'
}

main "$@"
