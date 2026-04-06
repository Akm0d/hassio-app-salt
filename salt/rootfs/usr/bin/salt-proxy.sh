#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Reverse proxy ingress traffic to SaltGUI.
# ==============================================================================

set -euo pipefail

main() {
    bashio::log.info "Starting lighttpd ingress proxy on 0.0.0.0:8099"
    exec lighttpd -D -f /etc/lighttpd/lighttpd.conf
}
main "$@"
