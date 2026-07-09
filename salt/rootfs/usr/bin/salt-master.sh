#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

readonly LOG_DIR="/srv/materium-dev/logs"
readonly MASTER_LOG="${LOG_DIR}/salt-master.log"

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${MASTER_LOG}"
    exec > >(tee -a "${MASTER_LOG}") 2>&1
}

main() {
    setup_logging
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    printf '[salt-master] Starting salt-master with config %s\n' "$(dirname "${MATERIUM_MASTER_CONFIG}")"
    cd "${MATERIUM_APP_DIR}"
    exec uv run --no-sync --extra test salt-master \
        -c "$(dirname "${MATERIUM_MASTER_CONFIG}")" \
        --log-file=/dev/stderr
}
main "$@"
