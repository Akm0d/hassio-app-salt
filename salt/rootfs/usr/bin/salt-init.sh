#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Prepare Salt master, SaltGUI, and ingress configuration.
# ==============================================================================

set -euo pipefail

generate_password() {
    local password=""

    while [[ "${#password}" -lt 24 ]]; do
        password+="$(
            tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$((24 - ${#password}))" || true
        )"
    done

    printf '%s' "${password:0:24}"
}

ensure_gui_password() {
    local configured_password="${1}"
    local generated_password_file="/data/generated_gui_password"

    if [[ -n "${configured_password}" ]]; then
        printf '%s' "${configured_password}"
        return 0
    fi

    if [[ ! -s "${generated_password_file}" ]]; then
        generate_password >"${generated_password_file}"
        chmod 0600 "${generated_password_file}"
    fi

    cat "${generated_password_file}"
}

ensure_gui_user() {
    local gui_username="${1}"
    local gui_password="${2}"

    if ! id -u "${gui_username}" >/dev/null 2>&1; then
        adduser -D -h /var/empty -s /bin/sh "${gui_username}" >/dev/null 2>&1
    fi

    printf '%s:%s\n' "${gui_username}" "${gui_password}" | chpasswd
}

ensure_share_tree() {
    mkdir -p /share/salt/states/example
    mkdir -p /share/salt/pillars

    if [[ ! -f /share/salt/states/top.sls ]]; then
        cat <<'EOF' >/share/salt/states/top.sls
base:
  '*':
    - example
EOF
    fi

    if [[ ! -f /share/salt/states/example/init.sls ]]; then
        cat <<'EOF' >/share/salt/states/example/init.sls
salt_example_state:
  test.succeed_without_changes:
    - name: Salt is connected to this Home Assistant master.
EOF
    fi

    if [[ ! -f /share/salt/pillars/top.sls ]]; then
        cat <<'EOF' >/share/salt/pillars/top.sls
base:
  '*': []
EOF
    fi
}

write_master_config() {
    local gui_username="${1}"
    local auto_accept="${2}"

    cat <<EOF >/etc/salt/master
interface: 0.0.0.0
publish_port: 4505
ret_port: 4506
auto_accept: ${auto_accept}
open_mode: False
user: root
pki_dir: /data/pki/master
cachedir: /data/cache/master
token_dir: /data/tokens
sqlite_queue_dir: /data/queues
pidfile: /run/salt-master.pid
sock_dir: /run/salt/master
fileserver_backend:
  - roots
file_roots:
  base:
    - /share/salt/states
pillar_roots:
  base:
    - /share/salt/pillars
netapi_enable_clients:
  - local
  - local_async
  - runner
  - wheel
external_auth:
  pam:
    ${gui_username}:
      - .*
      - '@runner'
      - '@wheel'
      - '@jobs'
rest_cherrypy:
  host: 0.0.0.0
  port: 3333
  disable_ssl: true
  debug: false
  app: /opt/saltgui/index.html
  static: /opt/saltgui/static
  static_path: /static
EOF
}

write_proxy_config() {
    cat <<'EOF' >/etc/lighttpd/lighttpd.conf
server.modules = (
    "mod_access",
    "mod_proxy",
    "mod_rewrite"
)

server.document-root = "/opt/saltgui"
server.errorlog = "/dev/stderr"
server.port = 8099
server.bind = "0.0.0.0"

url.rewrite-once = (
    "^/(api/)?hassio_ingress/[^/]+$" => "/",
    "^/(api/)?hassio_ingress/[^/]+/$" => "/",
    "^/(api/)?hassio_ingress/[^/]+/(.*)$" => "/$2"
)

proxy.server = (
    "" => (
        (
            "host" => "127.0.0.1",
            "port" => 3333
        )
    )
)

$HTTP["remoteip"] != "172.30.32.2" {
    url.access-deny = ( "" )
}
EOF
}

seed_saltgui_files() {
    printf 'CLEAR\npam\n' >/opt/saltgui/static/salt-auth.txt
    : >/opt/saltgui/static/minions.txt
}

main() {
    local auto_accept
    local gui_password
    local gui_password_effective
    local gui_username

    auto_accept="$(bashio::config 'auto_accept')"
    gui_password="$(bashio::config 'gui_password')"
    gui_username="$(bashio::config 'gui_username')"

    bashio::log.info "Preparing Salt master configuration"
    mkdir -p /data/pki/master /data/cache/master /data/tokens /data/queues /run/salt/master

    ensure_share_tree
    gui_password_effective="$(ensure_gui_password "${gui_password}")"
    ensure_gui_user "${gui_username}" "${gui_password_effective}"
    write_master_config "${gui_username}" "${auto_accept}"
    write_proxy_config
    seed_saltgui_files

    bashio::log.info "Salt state tree: /share/salt/states"
    bashio::log.info "Salt pillar tree: /share/salt/pillars"
    bashio::log.info "SaltGUI and salt-api will listen on port 3333"
    bashio::log.info "Salt master ports: 4505/4506"
    bashio::log.info "SaltGUI login user: ${gui_username}"

    if [[ -z "${gui_password}" ]]; then
        bashio::log.notice "Generated SaltGUI password for ${gui_username}: ${gui_password_effective}"
    fi
}
main "$@"
