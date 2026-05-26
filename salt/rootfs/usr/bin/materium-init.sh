#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly DATA_DIR="/data/materium"
readonly SYNCED_APP_DIR="/srv/materium-dev/materium"
readonly INIT_LOCK_DIR="/run/materium-init.lock"
readonly INIT_READY_FILE="/run/materium-init.ready"

log_info() {
    printf '[materium-init] %s\n' "$*"
}


acquire_init_lock() {
    while ! mkdir "${INIT_LOCK_DIR}" 2>/dev/null; do
        sleep 0.1
    done

    trap 'rmdir "${INIT_LOCK_DIR}" 2>/dev/null || true' EXIT
}

main() {
    local app_dir="/opt/materium"
    local uv_project_environment="/opt/materium/.venv"
    log_info "Starting materium init"

    acquire_init_lock
    mkdir -p "${DATA_DIR}"

    if [[ -f "${SYNCED_APP_DIR}/pyproject.toml" ]]; then
        log_info "Using development app from ${SYNCED_APP_DIR}"
        app_dir="${SYNCED_APP_DIR}"
        uv_project_environment="${DATA_DIR}/dev-venv"
    else
        log_info "Using production app from ${app_dir}"
    fi

    log_info "Writing Materium and Salt runtime configuration"
    MATERIUM_APP_DIR="${app_dir}" \
    UV_PROJECT_ENVIRONMENT="${uv_project_environment}" \
    UV_PYTHON_INSTALL_DIR_VALUE="${UV_PYTHON_INSTALL_DIR:-${DATA_DIR}/uv-python}" \
    python3 <<'PY'
import json
import os
import pathlib
import stat

import yaml

data_dir = pathlib.Path("/data/materium")
addon_config = pathlib.Path("/etc/materium-addon/config.yaml")
options_path = pathlib.Path("/data/options.json")
materium_config = data_dir / "materium.yaml"

manifest = yaml.safe_load(addon_config.read_text()) or {}
options = json.loads(options_path.read_text())

publish_port = manifest["ports"]["4505/tcp"]
ret_port = manifest["ports"]["4506/tcp"]
ingress_port = manifest["ingress_port"]

materium = dict(options["materium"])
materium["base_dir"] = str(data_dir)
materium["port"] = ingress_port

master = dict(options["master"])
master["publish_port"] = publish_port
master["ret_port"] = ret_port

minion = dict(options["minion"])
if minion.get("id") == "${HOSTNAME}":
    minion["id"] = os.environ["HOSTNAME"]

master_config = pathlib.Path(master["root_dir"]) / "etc" / "salt" / "master"
minion_config = pathlib.Path(minion["root_dir"]) / "etc" / "salt" / "minion"
for path in (materium_config, master_config, minion_config):
    path.parent.mkdir(parents=True, exist_ok=True)

materium_config.write_text(
    yaml.safe_dump(
        {"materium": materium, "master": master, "minion": minion},
        sort_keys=False,
    ),
)
master_config.write_text(yaml.safe_dump(master, sort_keys=False))
minion_config.write_text(yaml.safe_dump(minion, sort_keys=False))

env_path = pathlib.Path("/run/materium-env")
env_path.write_text(
    "\n".join(
        [
            f"export MATERIUM_APP_DIR={os.environ['MATERIUM_APP_DIR']}",
            f"export MATERIUM_CONFIG={materium_config}",
            f"export MATERIUM_MASTER_CONFIG={master_config}",
            f"export MATERIUM_MINION_CONFIG={minion_config}",
            f"export MATERIUM_MASTER_PUBLISH_PORT={publish_port}",
            f"export MATERIUM_MASTER_RET_PORT={ret_port}",
            f"export UV_PROJECT_ENVIRONMENT={os.environ['UV_PROJECT_ENVIRONMENT']}",
            "export UV_LINK_MODE=copy",
            "export UV_PYTHON=3.14",
            f"export UV_PYTHON_INSTALL_DIR={os.environ['UV_PYTHON_INSTALL_DIR_VALUE']}",
            "export CC=clang",
            "export CXX=clang++",
            "",
        ],
    ),
)
env_path.chmod(env_path.stat().st_mode | stat.S_IRUSR | stat.S_IWUSR)
PY

    log_info "App ready, releasing init lock and signaling readiness"
    touch "${INIT_READY_FILE}"
}

main "$@"
