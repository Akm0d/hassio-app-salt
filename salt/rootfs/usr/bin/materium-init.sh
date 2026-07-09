#!/usr/bin/env bash
# shellcheck shell=bash

set -euo pipefail

readonly DATA_DIR="/data/materium"
readonly CONFIG_DIR="/config/materium"
readonly SYNCED_APP_DIR="/srv/materium-dev/materium"
readonly INIT_LOCK_DIR="/run/materium-init.lock"
readonly INIT_READY_FILE="/run/materium-init.ready"
readonly LOG_DIR="/srv/materium-dev/logs"
readonly INIT_LOG="${LOG_DIR}/materium-init.log"

log_info() {
    printf '[materium-init] %s\n' "$*"
}

setup_logging() {
    mkdir -p "${LOG_DIR}"
    touch "${INIT_LOG}"
    exec > >(tee -a "${INIT_LOG}") 2>&1
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
    setup_logging
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
config_dir = pathlib.Path("/config/materium")
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
master["root_dir"] = str(config_dir / "salt" / "master")
master["publish_port"] = publish_port
master["ret_port"] = ret_port

master_config = pathlib.Path(master["root_dir"]) / "etc" / "salt" / "master"
for path in (materium_config, master_config):
    path.parent.mkdir(parents=True, exist_ok=True)

materium_config.write_text(
    yaml.safe_dump(
        {"materium": materium, "master": master},
        sort_keys=False,
    ),
)
master_config.write_text(yaml.safe_dump(master, sort_keys=False))

env_path = pathlib.Path("/run/materium-env")
env_path.write_text(
    "\n".join(
        [
            f"export MATERIUM_APP_DIR={os.environ['MATERIUM_APP_DIR']}",
            f"export MATERIUM_CONFIG={materium_config}",
            f"export MATERIUM_MASTER_CONFIG={master_config}",
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
    # shellcheck disable=SC1091
    source /run/materium-env
    log_info "Syncing Materium Python environment in ${UV_PROJECT_ENVIRONMENT}"
    (
        cd "${MATERIUM_APP_DIR}"
        uv sync --frozen --extra test
    )
    touch "${INIT_READY_FILE}"
}

main "$@"
