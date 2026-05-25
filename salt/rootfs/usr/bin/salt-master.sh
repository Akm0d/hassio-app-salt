#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    printf '[salt-master] Starting salt-master on ports 4505/4506\n'
    exec salt-master \
        -c /data/materium/master/etc/salt \
        -l "${MATERIUM_LOG_LEVEL}" \
        --log-file=/dev/stderr \
        --log-file-level="${MATERIUM_LOG_LEVEL}"
}
main "$@"
