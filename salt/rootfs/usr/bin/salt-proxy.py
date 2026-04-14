#!/usr/bin/env python3
"""Serve SaltGUI ingress and proxy Salt API requests."""

from __future__ import annotations

import http.client
import json
import mimetypes
import os
import posixpath
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from salt_ingress_auth_lib import authenticate_ingress

BOOTSTRAP_FILE = Path("/opt/ha-salt-ingress/index.html")
APP_DIR = Path("/opt/saltgui")
STATIC_DIR = APP_DIR / "static"
API_HOST = "127.0.0.1"
API_PORT = 3333
INGRESS_PREFIX = re.compile(r"^/(?:api/)?hassio_ingress/[^/]+(?P<rest>/.*)?$")
HOP_BY_HOP_HEADERS = {
    "connection",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailers",
    "transfer-encoding",
    "upgrade",
}
BOOTSTRAP_FALLBACK_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Salt</title>
</head>
<body>
  <p>Opening Salt...</p>
  <script>
    const ingressUrl = new URL(window.location.href);
    ingressUrl.search = "";
    ingressUrl.hash = "";
    ingressUrl.pathname = ingressUrl.pathname.replace(/\/+$/, "");
    const childUrl = (childPath) => {
      const url = new URL(ingressUrl.href);
      url.pathname = `${ingressUrl.pathname}/${childPath.replace(/^\/+/, "")}`;
      return url;
    };
    fetch(childUrl("__ha_salt_auth"), { credentials: "same-origin", cache: "no-store" })
      .then((response) => {
        if (!response.ok) {
          return response.json().then((payload) => Promise.reject(new Error(payload.message || "SaltGUI sign-in failed.")));
        }
        return response.json();
      })
      .then((payload) => {
        const loginResponse = payload?.result?.return?.[0];
        if (!loginResponse?.token) {
          throw new Error("SaltGUI sign-in returned an incomplete session.");
        }
        window.localStorage.setItem("eauth", "pam");
        window.sessionStorage.setItem("token", loginResponse.token);
        window.sessionStorage.setItem("login_response", JSON.stringify(loginResponse));
        window.location.replace(childUrl("app/"));
      })
      .catch((error) => {
        document.body.textContent = error.message || "SaltGUI sign-in failed.";
      });
  </script>
</body>
</html>
"""
LOGIN_HINT_SNIPPET = """
<script>
(() => {
  const USERNAME = "saltadmin";

  const applyLoginHints = () => {
    const passwordInput = document.querySelector('input[type="password"]');
    const usernameInput =
      document.querySelector('input[name="username"]') ||
      document.querySelector('input[id*="user" i]') ||
      document.querySelector('input[placeholder*="user" i]') ||
      (() => {
        const textInputs = Array.from(document.querySelectorAll('input[type="text"], input:not([type])'));
        return passwordInput && textInputs.length === 1 ? textInputs[0] : null;
      })();

    if (usernameInput && !usernameInput.value) {
      usernameInput.value = USERNAME;
      usernameInput.dispatchEvent(new Event("input", { bubbles: true }));
      usernameInput.dispatchEvent(new Event("change", { bubbles: true }));
    }

    if (passwordInput && !document.getElementById("ha-salt-login-hint")) {
      const hint = document.createElement("p");
      hint.id = "ha-salt-login-hint";
      hint.textContent = "Manual login username: saltadmin";
      hint.style.margin = "0.75rem 0 0";
      hint.style.fontSize = "0.9rem";
      hint.style.color = "#22c7bd";
      passwordInput.parentElement?.appendChild(hint);
    }
  };

  new MutationObserver(applyLoginHints).observe(document.documentElement, {
    childList: true,
    subtree: true,
  });
  window.addEventListener("DOMContentLoaded", applyLoginHints);
  applyLoginHints();
})();
</script>
"""


class SaltProxyHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        sys.stderr.write(f"[salt-proxy] {self.address_string()} - {format % args}\n")

    def do_GET(self) -> None:  # noqa: N802
        self.handle_request()

    def do_POST(self) -> None:  # noqa: N802
        self.handle_request()

    def do_PUT(self) -> None:  # noqa: N802
        self.handle_request()

    def do_DELETE(self) -> None:  # noqa: N802
        self.handle_request()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.handle_request()

    def handle_request(self) -> None:
        parsed = urllib.parse.urlsplit(self.path)
        request_path = self._strip_ingress_prefix(parsed.path)

        if request_path == "/":
            self._serve_bootstrap()
            return

        if request_path == "/__ha_salt_auth":
            self._handle_auth_bridge()
            return

        if request_path == "/app":
            self.send_response(302)
            self.send_header("Location", self._rebuilt_path("/app/", parsed.query))
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        if request_path.startswith("/app/"):
            self._serve_static(APP_DIR, request_path[len("/app/"):], spa_fallback=True)
            return

        if request_path.startswith("/static/"):
            self._serve_static(STATIC_DIR, request_path[len("/static/"):], spa_fallback=False)
            return

        backend_path = self._api_backend_path(request_path, parsed.query)
        if backend_path is not None:
            self._proxy_to_api(backend_path)
            return

        self.send_error(404, "Not Found")

    def _strip_ingress_prefix(self, path: str) -> str:
        match = INGRESS_PREFIX.match(path)
        if match:
            path = match.group("rest") or "/"
        return self._normalize_path(path or "/")

    def _rebuilt_path(self, path: str, query: str) -> str:
        return f"{path}?{query}" if query else path

    @staticmethod
    def _normalize_path(path: str) -> str:
        if not path:
            return "/"
        normalized = re.sub(r"/{2,}", "/", path)
        return "/" + normalized.lstrip("/")

    def _send_no_store_headers(self) -> None:
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Pragma", "no-cache")

    def _serve_file(self, path: Path, content_type: str | None = None) -> None:
        data = path.read_bytes()
        mime = content_type or mimetypes.guess_type(path.name)[0] or "application/octet-stream"

        self.send_response(200)
        self.send_header("Content-Type", mime)
        self._send_no_store_headers()
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_bootstrap(self) -> None:
        if BOOTSTRAP_FILE.is_file():
            data = BOOTSTRAP_FILE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Cache-Control", "no-store, max-age=0")
            self.send_header("Pragma", "no-cache")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        data = BOOTSTRAP_FALLBACK_HTML.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_static(self, base_dir: Path, relative_path: str, spa_fallback: bool) -> None:
        normalized = posixpath.normpath("/" + relative_path).lstrip("/")
        target = (base_dir / normalized).resolve()

        try:
            target.relative_to(base_dir.resolve())
        except ValueError:
            self.send_error(403, "Forbidden")
            return

        if target.is_dir():
            target = target / "index.html"

        if not target.exists() and spa_fallback:
            target = APP_DIR / "index.html"

        if not target.exists() or not target.is_file():
            self.send_error(404, "Not Found")
            return

        if target.name == "config.js" and target.parent.name == "scripts":
            self._serve_config_js(target)
            return

        if target == APP_DIR / "index.html":
            self._serve_app_index(target)
            return

        self._serve_file(target)

    def _serve_app_index(self, path: Path) -> None:
        html = path.read_text(encoding="utf-8")

        def add_cache_buster(match: re.Match[str]) -> str:
            attr = match.group("attr")
            quote = match.group("quote")
            value = match.group("value")
            if "?" in value:
                return match.group(0)
            return f"{attr}={quote}{value}?v=ha-ingress{quote}"

        html = re.sub(
            r'(?P<attr>(?:src|href))=(?P<quote>["\'])(?P<value>static/[^"\']+)(?P=quote)',
            add_cache_buster,
            html,
        )
        if LOGIN_HINT_SNIPPET not in html:
            html = html.replace("</body>", f"{LOGIN_HINT_SNIPPET}\n  </body>")
        data = html.encode("utf-8")

        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self._send_no_store_headers()
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _serve_config_js(self, path: Path) -> None:
        _ = path  # Keep the signature aligned with the static file handler.
        data = (
            "/* dynamically generated for Home Assistant ingress */\n"
            "/* eslint-disable no-unused-vars */\n"
            "const config = (() => {\n"
            "  const url = new URL(window.location.href);\n"
            "  url.search = \"\";\n"
            "  url.hash = \"\";\n"
            "  const pathname = url.pathname.replace(/\\/+/g, \"/\").replace(/\\/+$/, \"\");\n"
            "  const basePath = pathname.endsWith(\"/app\") ? pathname.slice(0, -4) || \"/\" : pathname || \"/\";\n"
            "  const normalizedBase = basePath === \"/\" ? \"/\" : `${basePath}/`;\n"
            "  return {\n"
            "    API_URL: new URL(\"api/\", `${url.origin}${normalizedBase}`).pathname.replace(/\\/+$/, \"\"),\n"
            "    NAV_URL: new URL(\"app\", `${url.origin}${normalizedBase}`).pathname,\n"
            "  };\n"
            "})();\n"
            "/* eslint-enable no-unused-vars */\n"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/javascript; charset=utf-8")
        self._send_no_store_headers()
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle_auth_bridge(self) -> None:
        status, extra_headers, payload = authenticate_ingress(
            self.headers.get("X-Remote-User-Id", ""),
            self.headers.get("X-Remote-User-Name", ""),
        )
        body = json.dumps(payload).encode("utf-8")

        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for key, value in extra_headers:
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def _api_backend_path(self, request_path: str, query: str) -> str | None:
        if request_path == "/api":
            request_path = "/"
        elif request_path.startswith("/api/"):
            request_path = request_path[4:] or "/"
        elif request_path not in {
            "/login",
            "/logout",
            "/run",
            "/events",
            "/jobs",
            "/keys",
            "/minions",
            "/stats",
            "/hook",
            "/ws",
        }:
            return None

        return self._rebuilt_path(request_path, query)

    def _proxy_to_api(self, backend_path: str) -> None:
        body = self._read_request_body()
        headers = {
            key: value
            for key, value in self.headers.items()
            if key.lower() not in HOP_BY_HOP_HEADERS
            and key.lower() not in {"host", "content-length", "accept-encoding"}
        }
        headers["Host"] = f"{API_HOST}:{API_PORT}"
        self._normalize_api_content_type(headers, body)

        connection = http.client.HTTPConnection(API_HOST, API_PORT, timeout=30)
        try:
            connection.request(self.command, backend_path, body=body, headers=headers)
            response = connection.getresponse()

            self.send_response(response.status, response.reason)
            for key, value in response.getheaders():
                if key.lower() in HOP_BY_HOP_HEADERS:
                    continue
                self.send_header(key, value)
            self.end_headers()

            while True:
                chunk = response.read(64 * 1024)
                if not chunk:
                    break
                self.wfile.write(chunk)
                self.wfile.flush()
        except OSError as err:
            payload = json.dumps(
                {
                    "ok": False,
                    "message": "Salt API proxy request failed.",
                    "details": str(err),
                }
            ).encode("utf-8")
            self.send_response(502, "Bad Gateway")
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            connection.close()

    def _read_request_body(self) -> bytes | None:
        length = self.headers.get("Content-Length")
        if not length:
            return None
        return self.rfile.read(int(length))

    @staticmethod
    def _normalize_api_content_type(headers: dict[str, str], body: bytes | None) -> None:
        if not body:
            return

        stripped = body.lstrip()
        if not stripped.startswith((b"{", b"[")):
            return

        content_type_key = next(
            (key for key in headers if key.lower() == "content-type"),
            None,
        )
        if content_type_key is None:
            headers["Content-Type"] = "application/json"
            return

        content_type = headers[content_type_key].split(";", 1)[0].strip().lower()
        if content_type in {"", "text/plain"}:
            headers[content_type_key] = "application/json"


def main() -> int:
    server = ThreadingHTTPServer(("0.0.0.0", 8099), SaltProxyHandler)
    print("[salt-proxy] serving SaltGUI ingress on http://0.0.0.0:8099", flush=True)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
