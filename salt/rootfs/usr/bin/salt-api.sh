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
    wait_for_master
    bashio::log.info "Starting Salt REST API WSGI server on 127.0.0.1:3333"
    exec python3 /usr/bin/salt-rest-api.py
}
main "$@"
