"""Data coordinator for the Salt integration."""

from __future__ import annotations

import logging
from typing import Any

from homeassistant.core import HomeAssistant
from homeassistant.helpers.update_coordinator import DataUpdateCoordinator, UpdateFailed

from .api import SaltApiClient, SaltApiError
from .const import DOMAIN, UPDATE_INTERVAL

_LOGGER = logging.getLogger(__name__)


class SaltDataUpdateCoordinator(DataUpdateCoordinator[list[dict[str, Any]]]):
    """Poll Salt minion grain data once for all entities."""

    def __init__(self, hass: HomeAssistant, api: SaltApiClient) -> None:
        super().__init__(
            hass,
            _LOGGER,
            name=DOMAIN,
            update_interval=UPDATE_INTERVAL,
            always_update=False,
        )
        self.api = api

    async def _async_update_data(self) -> list[dict[str, Any]]:
        try:
            return await self.api.minion_grains()
        except SaltApiError as exc:
            raise UpdateFailed(str(exc)) from exc

    def minion(self, minion_id: str) -> dict[str, Any] | None:
        """Return one minion row by id."""
        for row in self.data or []:
            if row.get("id") == minion_id:
                return row
        return None

