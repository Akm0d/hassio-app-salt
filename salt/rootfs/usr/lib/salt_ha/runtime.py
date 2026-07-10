"""Runtime helpers for the Home Assistant Salt add-on."""

from __future__ import annotations

import asyncio
import json
import os
import pathlib
import socket
import subprocess
import contextlib
from collections.abc import Iterable
from datetime import UTC, datetime
from typing import Any

import yaml


CONFIG_ROOT = pathlib.Path("/config/salt")
DATA_ROOT = pathlib.Path("/data/salt-ha-api")
MASTER_ROOT = CONFIG_ROOT / "master"
MASTER_CONFIG_DIR = MASTER_ROOT / "etc" / "salt"
MASTER_CONFIG = MASTER_CONFIG_DIR / "master"
PROXY_ROOT = CONFIG_ROOT / "proxies"
GRAINS_CACHE = DATA_ROOT / "grains.json"
ENV_PATH = pathlib.Path("/run/salt-ha-env")
ADDON_OPTIONS = pathlib.Path("/data/options.json")
ADDON_MANIFEST = pathlib.Path("/etc/salt-addon/config.yaml")


KEY_BUCKETS = {
    "minions": "accepted",
    "minions_pre": "pending",
    "minions_rejected": "rejected",
    "minions_denied": "denied",
}
KEY_DIRS = {target: source for source, target in KEY_BUCKETS.items()}


def utc_now() -> str:
    """Return an ISO UTC timestamp."""
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def read_json(path: pathlib.Path, default: Any) -> Any:
    """Read JSON from a path, returning a default for missing or invalid files."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def write_json(path: pathlib.Path, data: Any) -> None:
    """Write compact JSON atomically enough for the add-on use case."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f"{path.suffix}.tmp")
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(path)


def load_options() -> dict[str, Any]:
    """Load Home Assistant add-on options."""
    return read_json(ADDON_OPTIONS, {})


def load_manifest() -> dict[str, Any]:
    """Load the committed add-on manifest copy."""
    return yaml.safe_load(ADDON_MANIFEST.read_text(encoding="utf-8")) or {}


def master_config_dir() -> pathlib.Path:
    """Return the Salt master config directory."""
    return pathlib.Path(os.environ.get("SALT_HA_MASTER_CONFIG_DIR", MASTER_CONFIG_DIR))


def run_salt_command(args: list[str], timeout: int = 60) -> subprocess.CompletedProcess[str]:
    """Run a Salt CLI command against the add-on master config."""
    return subprocess.run(
        args,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
    )


async def run_blocking(func, *args, **kwargs):
    """Run a blocking callable without stalling aiohttp."""
    return await asyncio.to_thread(func, *args, **kwargs)


def _ids(value: Any) -> list[str]:
    """Normalize Salt key output ids to sorted strings."""
    if not isinstance(value, Iterable) or isinstance(value, (str, bytes, dict)):
        return []
    return sorted(str(item) for item in value)


def list_keys_sync() -> dict[str, list[str]]:
    """Return Salt key ids by Home Assistant-friendly status."""
    pki_dir = MASTER_ROOT / "pki" / "master"
    keys: dict[str, list[str]] = {}
    for status, dirname in KEY_DIRS.items():
        key_dir = pki_dir / dirname
        try:
            keys[status] = sorted(
                path.name for path in key_dir.iterdir() if path.is_file() and not path.name.startswith(".")
            )
        except FileNotFoundError:
            keys[status] = []
    return keys


async def list_keys() -> dict[str, list[str]]:
    """Return Salt key ids by status."""
    return await run_blocking(list_keys_sync)


def key_status_map(keys: dict[str, list[str]]) -> dict[str, str]:
    """Build an id to status map from key buckets."""
    statuses: dict[str, str] = {}
    for status, ids in keys.items():
        for minion_id in ids:
            statuses[minion_id] = status
    return statuses


def key_path(status: str, minion_id: str) -> pathlib.Path:
    """Return the PKI file path for a minion key status."""
    return MASTER_ROOT / "pki" / "master" / KEY_DIRS[status] / minion_id


def move_key(minion_id: str, source_statuses: list[str], target_status: str) -> dict[str, Any]:
    """Move one key between Salt PKI status directories."""
    target = key_path(target_status, minion_id)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        return {"ok": True, "status": target_status, "changed": False}

    for source_status in source_statuses:
        source = key_path(source_status, minion_id)
        if not source.exists():
            continue
        os.replace(source, target)
        return {"ok": True, "status": target_status, "changed": True}

    return {"ok": False, "error": "key not found"}


def delete_key(minion_id: str) -> dict[str, Any]:
    """Delete one key from every Salt PKI status directory."""
    removed: list[str] = []
    for status in KEY_DIRS:
        path = key_path(status, minion_id)
        with contextlib.suppress(FileNotFoundError):
            path.unlink()
            removed.append(status)

    cache = load_grains_cache()
    if minion_id in cache:
        cache.pop(minion_id, None)
        save_grains_cache(cache)

    return {"ok": bool(removed), "removed": sorted(removed)}


def manage_keys_sync(action: str, ids: list[str]) -> dict[str, dict[str, Any]]:
    """Accept, reject, or delete Salt minion keys."""
    results: dict[str, dict[str, Any]] = {}
    for minion_id in ids:
        if action == "accept":
            results[minion_id] = move_key(minion_id, ["pending", "rejected", "denied"], "accepted")
        elif action == "reject":
            results[minion_id] = move_key(minion_id, ["pending", "accepted", "denied"], "rejected")
        elif action == "delete":
            results[minion_id] = delete_key(minion_id)
        else:
            results[minion_id] = {"ok": False, "error": "unsupported action"}
    return results


async def manage_keys(action: str, ids: list[str]) -> dict[str, dict[str, Any]]:
    """Accept, reject, or delete Salt minion keys."""
    return await run_blocking(manage_keys_sync, action, ids)


def load_grains_cache() -> dict[str, dict[str, Any]]:
    """Load cached grain rows by minion id."""
    data = read_json(GRAINS_CACHE, {})
    return data if isinstance(data, dict) else {}


def save_grains_cache(cache: dict[str, dict[str, Any]]) -> None:
    """Persist cached grain rows."""
    write_json(GRAINS_CACHE, cache)


def proxy_config(minion_id: str) -> dict[str, Any]:
    """Load a persisted proxy minion config."""
    config_path = PROXY_ROOT / minion_id / "etc" / "salt" / "proxy"
    try:
        return yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    except FileNotFoundError:
        return {}


def docker_grains(container_name: str) -> dict[str, Any]:
    """Return Docker metadata as grains for one container proxy."""
    import docker

    client = docker.from_env(timeout=15)
    try:
        container = client.containers.get(container_name)
        container.reload()
        attrs = container.attrs or {}
    finally:
        client.close()

    config = attrs.get("Config") or {}
    state = attrs.get("State") or {}
    network_settings = attrs.get("NetworkSettings") or {}
    host_config = attrs.get("HostConfig") or {}
    labels = config.get("Labels") or {}
    networks = network_settings.get("Networks") or {}
    name = (attrs.get("Name") or "").lstrip("/") or container_name

    return {
        "kernel": "Linux",
        "os": "Docker",
        "os_family": "Docker",
        "virtual": "container",
        "virtual_subtype": "Docker",
        "id": container_name,
        "host": name,
        "fqdn": name,
        "docker": {
            "id": attrs.get("Id"),
            "name": name,
            "image": config.get("Image") or "",
            "status": state.get("Status"),
            "running": bool(state.get("Running")),
            "created": attrs.get("Created"),
            "restart_policy": host_config.get("RestartPolicy"),
            "labels": labels,
            "networks": sorted(networks),
            "ports": network_settings.get("Ports") or {},
        },
    }


def refresh_grains_sync(timeout: int = 20) -> dict[str, Any]:
    """Refresh cached grains for accepted Docker proxy minions."""
    accepted = list_keys_sync().get("accepted", [])
    now = utc_now()
    cache = load_grains_cache()
    updated: list[str] = []
    skipped: list[str] = []
    errors: dict[str, str] = {}

    for minion_id in accepted:
        config = proxy_config(minion_id)
        proxy = config.get("proxy") if isinstance(config, dict) else {}
        if not isinstance(proxy, dict) or proxy.get("proxytype") != "docker":
            skipped.append(minion_id)
            continue
        container_name = str(proxy.get("name") or minion_id)
        try:
            grains = docker_grains(container_name)
        except Exception as exc:
            errors[minion_id] = str(exc)
            continue
        cache[minion_id] = {
            "id": minion_id,
            "grains": grains,
            "last_refresh": now,
            "last_seen": now,
        }
        updated.append(minion_id)

    save_grains_cache(cache)
    return {
        "updated": sorted(updated),
        "skipped": sorted(skipped),
        "errors": errors,
        "last_refresh": now,
    }


async def refresh_grains(timeout: int = 20) -> dict[str, Any]:
    """Poll accepted minions for grains and persist successful responses."""
    return await run_blocking(refresh_grains_sync, timeout)


def minion_rows_sync() -> list[dict[str, Any]]:
    """Return merged minion rows from Salt keys and cached grains."""
    keys = list_keys_sync()
    statuses = key_status_map(keys)
    cache = load_grains_cache()
    all_ids = sorted(set(statuses) | set(cache))
    rows: list[dict[str, Any]] = []
    for minion_id in all_ids:
        cached = cache.get(minion_id, {})
        rows.append(
            {
                "id": minion_id,
                "key_status": statuses.get(minion_id, "unknown"),
                "online": None,
                "grains": cached.get("grains", {}),
                "last_seen": cached.get("last_seen"),
                "last_refresh": cached.get("last_refresh"),
            },
        )
    return rows


async def minion_rows() -> list[dict[str, Any]]:
    """Return merged minion rows from Salt keys and cached grains."""
    return await run_blocking(minion_rows_sync)


def write_runtime_config() -> None:
    """Write persistent Salt runtime config and environment exports."""
    options = load_options()
    manifest = load_manifest()
    master_options = options.get("master", {})
    docker_options = options.get("docker_proxy", {})
    ui_options = options.get("ui", {})

    publish_port = int(master_options.get("publish_port") or manifest["ports"]["4505/tcp"])
    ret_port = int(master_options.get("ret_port") or manifest["ports"]["4506/tcp"])
    ui_host = str(ui_options.get("host", "0.0.0.0"))
    ui_port = int(ui_options.get("port") or manifest.get("ingress_port", 8099))

    for path in (
        DATA_ROOT,
        MASTER_CONFIG_DIR,
        MASTER_ROOT / "pki" / "master",
        MASTER_ROOT / "cache",
        MASTER_ROOT / "sock",
        MASTER_ROOT / "srv" / "salt",
        MASTER_ROOT / "srv" / "pillar",
        PROXY_ROOT,
    ):
        path.mkdir(parents=True, exist_ok=True)

    master_config = {
        "interface": "0.0.0.0",
        "publish_port": publish_port,
        "ret_port": ret_port,
        "log_level": master_options.get("log_level", "info"),
        "log_file": "/dev/stderr",
        "auto_accept": bool(master_options.get("auto_accept", False)),
        "worker_threads": int(master_options.get("worker_threads", 50)),
        "pki_dir": str(MASTER_ROOT / "pki" / "master"),
        "cachedir": str(MASTER_ROOT / "cache"),
        "sock_dir": str(MASTER_ROOT / "sock"),
        "pidfile": "/run/salt-master.pid",
        "file_roots": {"base": [str(MASTER_ROOT / "srv" / "salt")]},
        "pillar_roots": {"base": [str(MASTER_ROOT / "srv" / "pillar")]},
    }
    MASTER_CONFIG.write_text(yaml.safe_dump(master_config, sort_keys=False), encoding="utf-8")

    env = {
        "SALT_HA_MASTER_CONFIG_DIR": str(MASTER_CONFIG_DIR),
        "SALT_HA_MASTER_CONFIG": str(MASTER_CONFIG),
        "SALT_HA_MASTER_PUBLISH_PORT": str(publish_port),
        "SALT_HA_MASTER_RET_PORT": str(ret_port),
        "SALT_HA_API_HOST": ui_host,
        "SALT_HA_API_PORT": str(ui_port),
        "SALT_HA_DATA_ROOT": str(DATA_ROOT),
        "SALT_HA_PROXY_ROOT": str(PROXY_ROOT),
        "SALT_HA_DOCKER_PROXY_ENABLED": "1" if docker_options.get("enabled", True) else "0",
        "SALT_HA_DOCKER_PROXY_INCLUDE_STOPPED": "1"
        if docker_options.get("include_stopped", True)
        else "0",
    }
    ENV_PATH.write_text(
        "\n".join(f"export {key}={value}" for key, value in env.items()) + "\n",
        encoding="utf-8",
    )


def health_sync() -> dict[str, Any]:
    """Return local add-on health information."""
    try:
        import salt.version

        salt_version = f"salt {salt.version.__version__}"
    except Exception as exc:
        salt_version = f"salt version unavailable: {exc}"

    ret_port = int(os.environ.get("SALT_HA_MASTER_RET_PORT", "4506"))
    master_ready = False
    try:
        with socket.create_connection(("127.0.0.1", ret_port), timeout=1):
            master_ready = True
    except OSError:
        master_ready = False

    return {
        "ok": master_ready,
        "salt": salt_version,
        "master_config": str(master_config_dir() / "master"),
        "master_ret_port": ret_port,
        "time": utc_now(),
    }


async def health() -> dict[str, Any]:
    """Return local add-on health information."""
    return await run_blocking(health_sync)


if __name__ == "__main__":
    write_runtime_config()
