#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Reverse proxy ingress traffic to SaltGUI.
# ==============================================================================

set -euo pipefail

main() {
    local rc=0

    bashio::log.info "Validating lighttpd ingress config"
    lighttpd -tt -f /etc/lighttpd/lighttpd.conf

    bashio::log.info "Starting lighttpd ingress proxy on 0.0.0.0:8099"
    lighttpd -D -f /etc/lighttpd/lighttpd.conf || rc=$?

    bashio::log.error "lighttpd exited with status ${rc}"
    exit "${rc}"
}
main "$@"
