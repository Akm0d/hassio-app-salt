"""Binary sensors for the Salt integration."""

from __future__ import annotations

from homeassistant.components.binary_sensor import BinarySensorEntity
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import EntityCategory
from homeassistant.core import HomeAssistant
from homeassistant.helpers.entity_platform import AddEntitiesCallback

from .const import DOMAIN
from .coordinator import SaltDataUpdateCoordinator
from .entity import SaltMinionEntity


async def async_setup_entry(
    hass: HomeAssistant,
    entry: ConfigEntry,
    async_add_entities: AddEntitiesCallback,
) -> None:
    """Set up Salt binary sensors."""
    coordinator: SaltDataUpdateCoordinator = hass.data[DOMAIN][entry.entry_id]
    async_add_entities(
        SaltMinionOnlineBinarySensor(coordinator, str(row["id"]))
        for row in coordinator.data or []
        if row.get("id") and row.get("key_status") == "accepted"
    )


class SaltMinionOnlineBinarySensor(SaltMinionEntity, BinarySensorEntity):
    """Report whether a Salt minion is currently known as online."""

    _attr_name = "Online"
    _attr_entity_category = EntityCategory.DIAGNOSTIC

    def __init__(self, coordinator: SaltDataUpdateCoordinator, minion_id: str) -> None:
        super().__init__(coordinator, minion_id)
        self._attr_unique_id = f"{minion_id}_online"

    @property
    def is_on(self) -> bool | None:
        """Return the minion online state."""
        online = self.minion.get("online")
        return online if isinstance(online, bool) else None

