#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Run salt-api once the master socket is reachable.
# ==============================================================================

set -euo pipefail

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        bashio::log.info "Waiting for salt-master to accept connections on 4506"
        sleep 2
    done
}

main() {
    /usr/bin/salt-init.sh
    local log_level

    log_level="$(bashio::config 'log_level')"
    wait_for_master
    bashio::log.info "Starting native salt-api on 127.0.0.1:3333"
    # Keep salt-api in the foreground so s6 can supervise it directly and the
    # CherryPy REST logs land in the add-on log stream.
    exec salt-api \
        -c /etc/salt \
        -l "${log_level}" \
        --log-file=/dev/stderr \
        --log-file-level="${log_level}"
}
main "$@"
