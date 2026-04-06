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
    local log_level

    log_level="$(bashio::config 'log_level')"

    wait_for_master
    bashio::log.info "Starting salt-api on port 3333"
    exec salt-api -c /etc/salt -l "${log_level}"
}
main "$@"
