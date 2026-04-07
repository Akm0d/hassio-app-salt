#!/usr/bin/env python3
"""Create a SaltGUI session for an authenticated Home Assistant ingress user."""

from __future__ import annotations

import json
import os
from salt_ingress_auth_lib import authenticate_ingress


def send_json(status: str, payload: dict, extra_headers: list[tuple[str, str]] | None = None) -> int:
    print(f"Status: {status}")
    print("Content-Type: application/json")
    if extra_headers:
        for key, value in extra_headers:
            print(f"{key}: {value}")
    print()
    print(json.dumps(payload))
    return 0

def main() -> int:
    status, extra_headers, payload = authenticate_ingress(
        os.environ.get("HTTP_X_REMOTE_USER_ID", ""),
        os.environ.get("HTTP_X_REMOTE_USER_NAME", ""),
    )
    http_status = {
        200: "200 OK",
        401: "401 Unauthorized",
        500: "500 Internal Server Error",
        502: "502 Bad Gateway",
    }.get(status, f"{status} Unknown")
    return send_json(http_status, payload, extra_headers=extra_headers)


if __name__ == "__main__":
    raise SystemExit(main())
