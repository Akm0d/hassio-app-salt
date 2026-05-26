#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

main() {
    /usr/bin/materium-init.sh
    # shellcheck disable=SC1091
    source /run/materium-env
    printf '[salt-master] Starting salt-master with config %s\n' "$(dirname "${MATERIUM_MASTER_CONFIG}")"
    exec salt-master \
        -c "$(dirname "${MATERIUM_MASTER_CONFIG}")" \
        --log-file=/dev/stderr
}
main "$@"
