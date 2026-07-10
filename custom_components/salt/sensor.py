"""Sensors for the Salt integration."""

from __future__ import annotations

from datetime import datetime
from typing import Any

from homeassistant.components.sensor import SensorDeviceClass, SensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback
from homeassistant.util import slugify

from .const import COMMON_GRAINS, DOMAIN
from .coordinator import SaltDataUpdateCoordinator
from .entity import SaltMinionEntity, flatten_grains


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up Salt sensors."""
    coordinator: SaltDataUpdateCoordinator = hass.data[DOMAIN][entry.entry_id]
    entities: list[SensorEntity] = []
    for row in coordinator.data or []:
        if not row.get("id") or row.get("key_status") != "accepted":
            continue
        minion_id = str(row["id"])
        entities.extend(
            [
                SaltMinionKeyStatusSensor(coordinator, minion_id),
                SaltMinionLastRefreshSensor(coordinator, minion_id),
            ],
        )
        grains = row.get("grains", {})
        if isinstance(grains, dict):
            for grain_key, value in flatten_grains(grains).items():
                entities.append(SaltMinionGrainSensor(coordinator, minion_id, grain_key, value))
    async_add_entities(entities)


class SaltMinionKeyStatusSensor(SaltMinionEntity, SensorEntity):
    """Expose a minion's Salt key status."""

    _attr_name = "Key status"
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator: SaltDataUpdateCoordinator, minion_id: str) -> None:
        super().__init__(coordinator, minion_id)
        self._attr_unique_id = f"{minion_id}_key_status"

    @property
    def native_value(self) -> str:
        """Return the Salt key status."""
        return str(self.minion.get("key_status", "unknown"))


class SaltMinionLastRefreshSensor(SaltMinionEntity, SensorEntity):
    """Expose the last grain refresh time."""

    _attr_name = "Last refresh"
    _attr_entity_category = EntityCategory.DIAGNOSTIC
    _attr_device_class = SensorDeviceClass.TIMESTAMP

    def __init__(self, coordinator: SaltDataUpdateCoordinator, minion_id: str) -> None:
        super().__init__(coordinator, minion_id)
        self._attr_unique_id = f"{minion_id}_last_refresh"

    @property
    def native_value(self) -> datetime | None:
        """Return the last grain refresh timestamp."""
        value = self.minion.get("last_refresh")
        if not isinstance(value, str):
            return None
        try:
            return datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return None


class SaltMinionGrainSensor(SaltMinionEntity, SensorEntity):
    """Expose one scalar Salt grain as a sensor."""

    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(
        self,
        coordinator: SaltDataUpdateCoordinator,
        minion_id: str,
        grain_key: str,
        initial_value: Any,
    ) -> None:
        super().__init__(coordinator, minion_id)
        self.grain_key = grain_key
        self._attr_name = grain_key
        self._attr_unique_id = f"{minion_id}_grain_{slugify(grain_key)}"
        self._attr_entity_registry_enabled_default = (
            grain_key in COMMON_GRAINS and initial_value is not None
        )

    @property
    def native_value(self) -> Any:
        """Return the latest scalar grain value."""
        return flatten_grains(self.grains).get(self.grain_key)
