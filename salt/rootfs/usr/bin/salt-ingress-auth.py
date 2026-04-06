#!/usr/bin/env python3
"""Create a SaltGUI session for an authenticated Home Assistant ingress user."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

AUTH_FILE = Path("/run/saltgui-ingress-auth.json")


def send_json(status: str, payload: dict, extra_headers: list[tuple[str, str]] | None = None) -> int:
    print(f"Status: {status}")
    print("Content-Type: application/json")
    if extra_headers:
        for key, value in extra_headers:
            print(f"{key}: {value}")
    print()
    print(json.dumps(payload))
    return 0


def load_credentials() -> tuple[str, str]:
    data = json.loads(AUTH_FILE.read_text())
    return data["username"], data["password"]


def main() -> int:
    remote_user_id = os.environ.get("HTTP_X_REMOTE_USER_ID", "").strip()
    remote_user_name = os.environ.get("HTTP_X_REMOTE_USER_NAME", "").strip()

    if not remote_user_id:
        return send_json(
            "401 Unauthorized",
            {"ok": False, "message": "Home Assistant ingress authentication is required."},
        )

    try:
        gui_username, gui_password = load_credentials()
    except (OSError, ValueError, KeyError) as err:
        return send_json(
            "500 Internal Server Error",
            {"ok": False, "message": "SaltGUI ingress credentials are unavailable.", "details": str(err)},
        )

    request = urllib.request.Request(
        "http://127.0.0.1:3333/login",
        data=urllib.parse.urlencode(
            {"username": gui_username, "password": gui_password, "eauth": "pam"}
        ).encode(),
        headers={"Accept": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.loads(response.read().decode("utf-8", errors="replace"))
            cookies = [
                (key, value)
                for key, value in response.getheaders()
                if key.lower() == "set-cookie"
            ]
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace")
        return send_json(
            "502 Bad Gateway",
            {
                "ok": False,
                "message": "SaltGUI rejected the automatic ingress login request.",
                "details": body,
            },
        )
    except OSError as err:
        return send_json(
            "502 Bad Gateway",
            {"ok": False, "message": "SaltGUI is not reachable.", "details": str(err)},
        )

    return send_json(
        "200 OK",
        {
            "ok": True,
            "message": f"Authenticated {remote_user_name or remote_user_id}",
            "result": payload,
        },
        extra_headers=cookies,
    )


if __name__ == "__main__":
    raise SystemExit(main())
