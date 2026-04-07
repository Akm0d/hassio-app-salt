#!/usr/bin/env python3
"""Shared SaltGUI ingress authentication helpers."""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

AUTH_FILE = Path("/run/saltgui-ingress-auth.json")
API_LOGIN_URL = "http://127.0.0.1:3333/login"


def load_credentials() -> tuple[str, str]:
    data = json.loads(AUTH_FILE.read_text())
    return data["username"], data["password"]


def authenticate_ingress(remote_user_id: str, remote_user_name: str) -> tuple[int, list[tuple[str, str]], dict]:
    remote_user_id = remote_user_id.strip()
    remote_user_name = remote_user_name.strip()

    if not remote_user_id:
        return 401, [], {
            "ok": False,
            "message": "Home Assistant ingress authentication is required.",
        }

    try:
        gui_username, gui_password = load_credentials()
    except (OSError, ValueError, KeyError) as err:
        return 500, [], {
            "ok": False,
            "message": "SaltGUI ingress credentials are unavailable.",
            "details": str(err),
        }

    request = urllib.request.Request(
        API_LOGIN_URL,
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
        return 502, [], {
            "ok": False,
            "message": "SaltGUI rejected the automatic ingress login request.",
            "details": body,
        }
    except OSError as err:
        return 502, [], {
            "ok": False,
            "message": "SaltGUI is not reachable.",
            "details": str(err),
        }

    return 200, cookies, {
        "ok": True,
        "message": f"Authenticated {remote_user_name or remote_user_id}",
        "result": payload,
    }
