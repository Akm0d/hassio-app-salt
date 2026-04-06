#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Run salt-api once the master socket is reachable.
# ==============================================================================

set -euo pipefail

readonly API_PIDFILE="/run/salt-api.pid"

wait_for_master() {
    until bash -c ":</dev/tcp/127.0.0.1/4506" >/dev/null 2>&1; do
        bashio::log.info "Waiting for salt-master to accept connections on 4506"
        sleep 2
    done
}

api_is_listening() {
    bash -c ":</dev/tcp/127.0.0.1/3333" >/dev/null 2>&1
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

wait_for_api_listener() {
    local deadline=$((SECONDS + 15))

    while (( SECONDS < deadline )); do
        if api_is_listening; then
            bashio::log.info "salt-api is listening on 127.0.0.1:3333"
            return 0
        fi

        sleep 1
    done

    bashio::log.error "salt-api did not start listening on 127.0.0.1:3333"
    return 1
}

shutdown_api() {
    if [[ -f "${API_PIDFILE}" ]]; then
        local pid

        pid="$(cat "${API_PIDFILE}" 2>/dev/null || true)"
        if [[ -n "${pid}" ]] && kill -0 "${pid}" >/dev/null 2>&1; then
            kill "${pid}" >/dev/null 2>&1 || true
            wait "${pid}" 2>/dev/null || true
        fi
    fi
}

main() {
    local log_level

    log_level="$(bashio::config 'log_level')"

    wait_for_master
    cleanup_stale_pidfile

    if [[ -f "${API_PIDFILE}" ]]; then
        bashio::log.info "salt-api is already running"
    else
        bashio::log.info "Starting salt-api on port 3333"
        salt-api -d --pid-file="${API_PIDFILE}" -c /etc/salt -l "${log_level}"
    fi

    trap shutdown_api TERM INT
    wait_for_api_listener

    while true; do
        if ! api_is_listening; then
            bashio::log.error "salt-api exited unexpectedly"
            return 1
        fi
        sleep 5
    done
}
main "$@"
