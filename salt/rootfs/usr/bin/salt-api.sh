#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Run salt-api once the master socket is reachable.
# ==============================================================================

set -euo pipefail

readonly API_PIDFILE="/run/salt-api.pid"
readonly API_LOGFILE="/run/salt-api.log"
readonly CHERRYPY_ERROR_LOG="/run/salt-api-error.log"
readonly CHERRYPY_ACCESS_LOG="/run/salt-api-access.log"

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        bashio::log.info "Waiting for salt-master to accept connections on 4506"
        sleep 2
    done
}

dump_cherrypy_logs() {
    if [[ -s "${API_LOGFILE}" ]]; then
        bashio::log.error "Salt API daemon log follows"
        sed 's/^/[salt-api] /' "${API_LOGFILE}"
    fi

    if [[ -s "${CHERRYPY_ERROR_LOG}" ]]; then
        bashio::log.error "Salt API CherryPy error log follows"
        sed 's/^/[cherrypy:error] /' "${CHERRYPY_ERROR_LOG}"
    fi

    if [[ -s "${CHERRYPY_ACCESS_LOG}" ]]; then
        bashio::log.info "Salt API CherryPy access log follows"
        sed 's/^/[cherrypy:access] /' "${CHERRYPY_ACCESS_LOG}"
    fi
}

cleanup_stale_pidfile() {
    if [[ -f "${API_PIDFILE}" ]]; then
        local pid

        pid="$(cat "${API_PIDFILE}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
            return 0
        fi
        rm -f "${API_PIDFILE}"
    fi
}

api_is_listening() {
    bash -c ":</dev/tcp/127.0.0.1/3333" >/dev/null 2>&1
}

wait_for_api_listener() {
    local deadline=$((SECONDS + 180))

    while (( SECONDS < deadline )); do
        if api_is_listening; then
            bashio::log.info "salt-api is listening on 127.0.0.1:3333"
            return 0
        fi
        sleep 2
    done

    bashio::log.error "salt-api did not start listening on 127.0.0.1:3333"
    return 1
}

main() {
    local log_level
    local rc=0

    log_level="$(bashio::config 'log_level')"
    wait_for_master
    bashio::log.info "Starting salt-api on port 3333"
    cleanup_stale_pidfile
    rm -f "${API_LOGFILE}" "${CHERRYPY_ERROR_LOG}" "${CHERRYPY_ACCESS_LOG}"

    # SaltGUI's reference setup uses daemon mode for salt-api. We supervise the
    # daemon by waiting for the listener and then tracking the pidfile.
    salt-api -d \
        -c /etc/salt \
        -l "${log_level}" \
        --log-file="${API_LOGFILE}" \
        --log-file-level="${log_level}" || rc=$?

    if (( rc != 0 )); then
        bashio::log.error "salt-api daemon bootstrap exited with status ${rc}"
        dump_cherrypy_logs
        exit "${rc}"
    fi

    if ! wait_for_api_listener; then
        dump_cherrypy_logs
        exit 1
    fi

    while true; do
        local pid=""

        if [[ -f "${API_PIDFILE}" ]]; then
            pid="$(cat "${API_PIDFILE}" 2>/dev/null || true)"
        fi

        if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1 && api_is_listening; then
            sleep 5
            continue
        fi

        bashio::log.error "salt-api is no longer running"
        dump_cherrypy_logs
        exit 1
    done
}
main "$@"
