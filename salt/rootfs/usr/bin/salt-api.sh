#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Run salt-api once the master socket is reachable.
# ==============================================================================

set -euo pipefail

readonly CHERRYPY_ERROR_LOG="/run/salt-api-error.log"
readonly CHERRYPY_ACCESS_LOG="/run/salt-api-access.log"

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        bashio::log.info "Waiting for salt-master to accept connections on 4506"
        sleep 2
    done
}

dump_cherrypy_logs() {
    if [[ -s "${CHERRYPY_ERROR_LOG}" ]]; then
        bashio::log.error "Salt API CherryPy error log follows"
        sed 's/^/[cherrypy:error] /' "${CHERRYPY_ERROR_LOG}"
    fi

    if [[ -s "${CHERRYPY_ACCESS_LOG}" ]]; then
        bashio::log.info "Salt API CherryPy access log follows"
        sed 's/^/[cherrypy:access] /' "${CHERRYPY_ACCESS_LOG}"
    fi
}

main() {
    local log_level
    local rc=0

    log_level="$(bashio::config 'log_level')"
    wait_for_master
    bashio::log.info "Starting salt-api on port 3333"
    rm -f "${CHERRYPY_ERROR_LOG}" "${CHERRYPY_ACCESS_LOG}"
    # Salt recommends foreground mode under an external supervisor so failures
    # are visible in the container log instead of disappearing behind daemonization.
    salt-api \
        -c /etc/salt \
        -l "${log_level}" \
        --log-file=/dev/stderr \
        --log-file-level="${log_level}"
    rc=$?

    bashio::log.error "salt-api exited with status ${rc}"
    dump_cherrypy_logs
    exit "${rc}"
}
main "$@"
