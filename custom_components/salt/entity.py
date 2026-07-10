"""Entity helpers for the Salt integration."""

from __future__ import annotations

from typing import Any

from homeassistant.helpers.device_registry import DeviceInfo
from homeassistant.helpers.update_coordinator import CoordinatorEntity

from .const import DOMAIN
from .coordinator import SaltDataUpdateCoordinator


class SaltMinionEntity(CoordinatorEntity[SaltDataUpdateCoordinator]):
    """Base entity attached to one Salt minion device."""

    _attr_has_entity_name = True

    def __init__(self, coordinator: SaltDataUpdateCoordinator, minion_id: str) -> None:
        super().__init__(coordinator)
        self.minion_id = minion_id

    @property
    def minion(self) -> dict[str, Any]:
        """Return the latest minion row."""
        return self.coordinator.minion(self.minion_id) or {"id": self.minion_id, "grains": {}}

    @property
    def grains(self) -> dict[str, Any]:
        """Return the latest grains for this minion."""
        grains = self.minion.get("grains", {})
        return grains if isinstance(grains, dict) else {}

    @property
    def device_info(self) -> DeviceInfo:
        """Return Home Assistant device metadata."""
        grains = self.grains
        return DeviceInfo(
            identifiers={(DOMAIN, self.minion_id)},
            name=f"Salt minion {self.minion_id}",
            manufacturer="Salt Project",
            model=str(grains.get("os") or grains.get("kernel") or "Minion"),
            sw_version=str(grains.get("saltversion") or "") or None,
        )


def scalar(value: Any) -> bool:
    """Return whether a grain value can be represented as a sensor state."""
    return value is None or isinstance(value, (str, int, float, bool))


def flatten_grains(grains: dict[str, Any], prefix: str = "") -> dict[str, Any]:
    """Flatten nested grain dictionaries with dot-separated keys."""
    flattened: dict[str, Any] = {}
    for key, value in grains.items():
        path = f"{prefix}.{key}" if prefix else str(key)
        if isinstance(value, dict):
            flattened.update(flatten_grains(value, path))
        elif scalar(value):
            flattened[path] = value
    return flattened

