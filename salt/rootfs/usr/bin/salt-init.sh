#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Salt
# Prepare Salt master, SaltGUI, and ingress configuration.
# ==============================================================================

set -euo pipefail

readonly SALT_GUI_USERNAME="saltadmin"

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
    mkdir -p /srv/salt
    mkdir -p /srv/pillar

    if [[ ! -f /srv/salt/top.sls ]]; then
        cat <<'EOF' >/srv/salt/top.sls
# Define your top file targets here.
base: {}
EOF
    fi

    if [[ ! -f /srv/pillar/top.sls ]]; then
        cat <<'EOF' >/srv/pillar/top.sls
# Define your pillar top file targets here.
base: {}
EOF
    fi
}

write_master_config() {
    local auto_accept="${1}"

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
api_pidfile: /run/salt-api.pid
api_logfile: /run/salt-api.log
pidfile: /run/salt-master.pid
sock_dir: /run/salt/master
state_events: True
fileserver_backend:
  - roots
file_roots:
  base:
    - /srv/salt
pillar_roots:
  base:
    - /srv/pillar
netapi_enable_clients:
  - local
  - local_async
  - runner
  - wheel
external_auth:
  pam:
    ${SALT_GUI_USERNAME}:
      - .*
      - '@runner'
      - '@wheel'
      - '@jobs'
rest_cherrypy:
  host: 0.0.0.0
  port: 3333
  disable_ssl: true
  debug: false
  log_access_file: /run/salt-api-access.log
  log_error_file: /run/salt-api-error.log
  app: /opt/saltgui/index.html
  static: /opt/saltgui/static
  static_path: /static
EOF
}

verify_salt_runtime() {
    python3 - <<'EOF'
import importlib
import sys

required = [
    "salt",
    "salt.netapi.rest_cherrypy.app",
    "cherrypy",
    "ws4py",
    "pam",
]

failed = []
for name in required:
    try:
        importlib.import_module(name)
        print(f"runtime check ok: {name}")
    except Exception as err:  # pragma: no cover - startup only
        failed.append((name, err))
        print(f"runtime check failed: {name}: {err}", file=sys.stderr)

if failed:
    raise SystemExit(1)
EOF
}

write_proxy_config() {
    cat <<'EOF' >/etc/lighttpd/lighttpd.conf
server.modules = (
    "mod_access",
    "mod_alias",
    "mod_cgi",
    "mod_proxy",
    "mod_rewrite"
)

server.document-root = "/opt/ha-salt-ingress"
server.errorlog = "/dev/stderr"
server.port = 8099
server.bind = "0.0.0.0"
index-file.names = ( "index.html" )

alias.url = (
    "/__ha_salt_auth" => "/usr/bin/salt-ingress-auth.py"
)

cgi.assign = (
    ".py" => "/usr/bin/python3"
)

url.rewrite-once = (
    "^/(api/)?hassio_ingress/[^/]+$" => "/",
    "^/(api/)?hassio_ingress/[^/]+/$" => "/",
    "^/(api/)?hassio_ingress/[^/]+/(.*)$" => "/$2"
)

$HTTP["url"] =~ "^/(app|login|logout|run|events|jobs|keys|minions|stats|hook|ws|static|api)(/.*)?$" {
    proxy.server = (
        "" => (
            (
                "host" => "127.0.0.1",
                "port" => 3333
            )
        )
    )
}

$HTTP["remoteip"] != "172.30.32.2" {
    url.access-deny = ( "" )
}
EOF
}

write_ingress_bootstrap() {
    cat <<'EOF' >/opt/ha-salt-ingress/index.html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Salt</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #08141a;
      --panel: #102229;
      --text: #e6f9f7;
      --muted: #a5cbc7;
      --accent: #22c7bd;
      --danger: #ff9f9f;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      display: grid;
      place-items: center;
      background:
        radial-gradient(circle at top, rgba(34, 199, 189, 0.2), transparent 26rem),
        var(--bg);
      color: var(--text);
      font-family: "DejaVu Sans", sans-serif;
    }
    main {
      width: min(32rem, calc(100vw - 2rem));
      padding: 2rem;
      border-radius: 1.25rem;
      background: var(--panel);
      box-shadow: 0 1.5rem 3rem rgba(0, 0, 0, 0.3);
    }
    h1 {
      margin: 0 0 0.75rem;
      font-size: 1.8rem;
    }
    p {
      margin: 0;
      line-height: 1.5;
      color: var(--muted);
    }
    .status {
      margin-top: 1rem;
      color: var(--accent);
      font-weight: 700;
    }
    .status.error {
      color: var(--danger);
    }
  </style>
</head>
<body>
  <main>
    <h1>Opening Salt</h1>
    <p>Home Assistant is signing this admin session into SaltGUI.</p>
    <p class="status" id="status">Signing in...</p>
  </main>
  <script>
    const statusEl = document.getElementById("status");

    function ingressBaseUrl() {
      const url = new URL(window.location.href);
      url.search = "";
      url.hash = "";
      if (!url.pathname.endsWith("/")) {
        url.pathname = `${url.pathname}/`;
      }
      return url;
    }

    async function fail(response) {
      try {
        const payload = await response.json();
        statusEl.textContent = payload.message || "SaltGUI sign-in failed.";
      } catch (_error) {
        statusEl.textContent = "SaltGUI sign-in failed.";
      }
      statusEl.classList.add("error");
    }

    async function boot() {
      const baseUrl = ingressBaseUrl();
      const authUrl = new URL("__ha_salt_auth", baseUrl);
      const appUrl = new URL("app/", baseUrl);

      try {
        const response = await fetch(authUrl, {
          credentials: "same-origin",
          cache: "no-store"
        });
        if (!response.ok) {
          await fail(response);
          return;
        }
        window.location.replace(appUrl);
      } catch (_error) {
        statusEl.textContent = "Could not reach the Salt ingress bridge.";
        statusEl.classList.add("error");
      }
    }

    void boot();
  </script>
</body>
</html>
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

    auto_accept="$(bashio::config 'auto_accept')"
    gui_password="$(bashio::config 'gui_password')"

    bashio::log.info "Preparing Salt master configuration"
    mkdir -p /data/pki/master /data/cache/master /data/tokens /data/queues /run/salt/master /opt/ha-salt-ingress

    ensure_share_tree
    gui_password_effective="$(ensure_gui_password "${gui_password}")"
    ensure_gui_user "${SALT_GUI_USERNAME}" "${gui_password_effective}"
    write_master_config "${auto_accept}"
    verify_salt_runtime
    write_proxy_config
    write_ingress_bootstrap
    seed_saltgui_files
    SALT_GUI_USERNAME="${SALT_GUI_USERNAME}" SALT_GUI_PASSWORD="${gui_password_effective}" python3 - <<'EOF'
import json
import os
from pathlib import Path

Path("/run/saltgui-ingress-auth.json").write_text(
    json.dumps(
        {
            "username": os.environ["SALT_GUI_USERNAME"],
            "password": os.environ["SALT_GUI_PASSWORD"],
        }
    )
)
Path("/run/saltgui-ingress-auth.json").chmod(0o600)
EOF

    bashio::log.info "Salt state tree: /srv/salt (host path: /share/salt)"
    bashio::log.info "Salt pillar tree: /srv/pillar (host path: /share/pillar)"
    bashio::log.info "SaltGUI is available through the admin-only Home Assistant sidebar panel"
    bashio::log.info "salt-api will listen on internal port 3333"
    bashio::log.info "Salt master ports: 4505/4506"
    bashio::log.info "SaltGUI service account: ${SALT_GUI_USERNAME}"

    if [[ -z "${gui_password}" ]]; then
        bashio::log.notice "Generated SaltGUI password for ${SALT_GUI_USERNAME}: ${gui_password_effective}"
    fi
}
main "$@"
