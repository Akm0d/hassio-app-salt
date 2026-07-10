"""Docker proxy-minion support for the Salt Home Assistant add-on."""

from __future__ import annotations

import importlib
from typing import Any

__proxyenabled__ = ["docker"]

__virtualname__ = "docker"

__opts__: dict[str, Any]

CLIENT = None
CONTAINER_NAME = ""


def __virtual__():
    """Load as the docker proxy module."""
    return __virtualname__


def _docker():
    """Return the external Docker SDK module without shadowing this module."""
    return importlib.import_module("docker")


def _client():
    """Return a cached Docker client."""
    global CLIENT
    if CLIENT is None:
        CLIENT = _docker().from_env(timeout=15)
    return CLIENT


def _container():
    """Return the Docker container represented by this proxy minion."""
    return _client().containers.get(CONTAINER_NAME)


def _safe_attrs() -> dict[str, Any]:
    """Return container attrs or an empty dict when the container disappeared."""
    try:
        container = _container()
        container.reload()
        return container.attrs or {}
    except Exception:
        return {}


def init(opts: dict[str, Any]) -> bool:
    """Initialize the proxy minion from Salt proxy options."""
    global CONTAINER_NAME
    proxy_opts = opts.get("proxy", {})
    CONTAINER_NAME = str(proxy_opts.get("name") or opts.get("id") or "")
    return bool(CONTAINER_NAME)


def initialized() -> bool:
    """Return whether the proxy has enough configuration to operate."""
    return bool(CONTAINER_NAME)


def shutdown(opts: dict[str, Any] | None = None) -> None:
    """Close the Docker client on proxy shutdown."""
    global CLIENT
    if CLIENT is not None:
        try:
            CLIENT.close()
        except Exception:
            pass
    CLIENT = None


def ping() -> bool:
    """Return true when the represented container is visible."""
    try:
        _container()
        return True
    except Exception:
        return False


def alive(opts: dict[str, Any] | None = None) -> bool:
    """Return true when the represented container is visible."""
    return ping()


def grains() -> dict[str, Any]:
    """Expose Docker container metadata as Salt grains."""
    attrs = _safe_attrs()
    config = attrs.get("Config") or {}
    state = attrs.get("State") or {}
    network_settings = attrs.get("NetworkSettings") or {}
    host_config = attrs.get("HostConfig") or {}
    image = config.get("Image") or ""
    labels = config.get("Labels") or {}
    networks = network_settings.get("Networks") or {}

    return {
        "kernel": "Linux",
        "os": "Docker",
        "os_family": "Docker",
        "virtual": "container",
        "virtual_subtype": "Docker",
        "id": CONTAINER_NAME,
        "host": CONTAINER_NAME,
        "fqdn": CONTAINER_NAME,
        "docker": {
            "id": attrs.get("Id"),
            "name": (attrs.get("Name") or "").lstrip("/") or CONTAINER_NAME,
            "image": image,
            "status": state.get("Status"),
            "running": bool(state.get("Running")),
            "created": attrs.get("Created"),
            "restart_policy": host_config.get("RestartPolicy"),
            "labels": labels,
            "networks": sorted(networks),
            "ports": network_settings.get("Ports") or {},
        },
    }
