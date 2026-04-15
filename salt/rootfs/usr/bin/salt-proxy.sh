#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Reverse proxy ingress traffic to SaltGUI.
# ==============================================================================

set -euo pipefail

wait_for_api() {
    until bash -c ":</dev/tcp/127.0.0.1/3333" >/dev/null 2>&1; do
        bashio::log.info "Waiting for Salt REST API to accept connections on 3333"
        sleep 2
    done
}

main() {
    local saltgui_theme

    /usr/bin/salt-init.sh
    wait_for_api
    saltgui_theme="$(bashio::config 'saltgui_theme')"
    bashio::log.info "Starting SaltGUI ingress proxy on 0.0.0.0:8099"
    SALTGUI_THEME="${saltgui_theme}" exec python3 /usr/bin/salt-proxy.py
}
main "$@"
