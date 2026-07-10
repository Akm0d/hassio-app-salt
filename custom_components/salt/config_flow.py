"""Config flow for the Salt integration."""

from __future__ import annotations

from typing import Any

import voluptuous as vol

from homeassistant import config_entries
from homeassistant.core import HomeAssistant
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from .api import SaltApiClient, SaltApiError
from .const import CONF_URL, DEFAULT_NAME, DEFAULT_URL, DOMAIN


async def validate_input(hass: HomeAssistant, data: dict[str, Any]) -> None:
    """Validate that the Salt API is reachable."""
    api = SaltApiClient(async_get_clientsession(hass), data[CONF_URL])
    await api.health()


class SaltConfigFlow(config_entries.ConfigFlow, domain=DOMAIN):
    """Handle a Salt config flow."""

    VERSION = 1

    async def async_step_user(
        self,
        user_input: dict[str, Any] | None = None,
    ) -> config_entries.ConfigFlowResult:
        """Handle the initial step."""
        errors: dict[str, str] = {}

        if user_input is not None:
            await self.async_set_unique_id(user_input[CONF_URL].rstrip("/"))
            self._abort_if_unique_id_configured()
            try:
                await validate_input(self.hass, user_input)
            except SaltApiError:
                errors["base"] = "cannot_connect"
            else:
                return self.async_create_entry(title=DEFAULT_NAME, data=user_input)

        schema = vol.Schema({vol.Required(CONF_URL, default=DEFAULT_URL): str})
        return self.async_show_form(step_id="user", data_schema=schema, errors=errors)

