#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        printf '[salt-minion] Waiting for salt-master to accept connections on 4506\n'
        sleep 2
    done
}

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    wait_for_master
    printf '[salt-minion] Starting local salt-minion\n'
    exec salt-minion \
        -c /data/materium/minion/etc/salt \
        -l "${MATERIUM_LOG_LEVEL}" \
        --log-file=/dev/stderr \
        --log-file-level="${MATERIUM_LOG_LEVEL}"
}

main "$@"
