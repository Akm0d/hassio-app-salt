"""API client for the Salt add-on."""

from __future__ import annotations

from typing import Any

from aiohttp import ClientError, ClientSession


class SaltApiError(Exception):
    """Raised when the Salt add-on API cannot be read."""


class SaltApiClient:
    """Small async client for the Salt add-on API."""

    def __init__(self, session: ClientSession, base_url: str) -> None:
        self._session = session
        self._base_url = base_url.rstrip("/")

    async def _json(self, path: str) -> dict[str, Any]:
        url = f"{self._base_url}{path}"
        try:
            async with self._session.get(url, timeout=30) as response:
                response.raise_for_status()
                payload = await response.json()
        except (ClientError, TimeoutError) as exc:
            raise SaltApiError(str(exc)) from exc
        if not isinstance(payload, dict):
            raise SaltApiError(f"Unexpected Salt API response from {url}")
        return payload

    async def health(self) -> dict[str, Any]:
        """Return add-on health."""
        return await self._json("/api/health")

    async def minion_grains(self) -> list[dict[str, Any]]:
        """Return minion rows with cached grains."""
        payload = await self._json("/api/minions/grains")
        data = payload.get("data", [])
        if not isinstance(data, list):
            raise SaltApiError("Salt API returned invalid minion data")
        return [row for row in data if isinstance(row, dict)]

