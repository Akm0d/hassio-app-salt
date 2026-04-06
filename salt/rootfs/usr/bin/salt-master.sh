#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Run salt-master in the foreground.
# ==============================================================================

set -euo pipefail

main() {
    local log_level

    log_level="$(bashio::config 'log_level')"
    bashio::log.info "Starting salt-master on ports 4505/4506"
    exec salt-master --disable-keepalive -c /etc/salt -l "${log_level}"
}
main "$@"
