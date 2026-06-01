#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly RESTART_MARKER="/srv/materium-dev/restart"
readonly RESTART_LOG="/srv/materium-dev/reloader.log"

setup_logging() {
    mkdir -p "$(dirname "${RESTART_LOG}")"
    touch "${RESTART_LOG}"
    exec > >(tee -a "${RESTART_LOG}") 2>&1
}

log_info() {
    printf '[materium-dev-reloader] %s\n' "$*"
}

restart_materium() {
    log_info "Restarting materium-web and materium-worker"
    s6-rc -d change materium-web materium-worker || true
    s6-rc -u change materium-web materium-worker
}

main() {
    setup_logging
    /usr/bin/materium-init.sh
    mkdir -p "$(dirname "${RESTART_MARKER}")"
    log_info "Watching ${RESTART_MARKER}"

    while true; do
        if [[ -f "${RESTART_MARKER}" ]]; then
            rm -f "${RESTART_MARKER}"
            restart_materium
        fi
        sleep 1
    done
}

main "$@"
