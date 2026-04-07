#!/usr/bin/env python3
"""Serve Salt's rest_cherrypy WSGI app without the salt-api daemon wrapper."""

from __future__ import annotations

import os
import sys
from socketserver import ThreadingMixIn
from wsgiref.simple_server import WSGIRequestHandler, WSGIServer, make_server

os.environ.setdefault("SALT_MASTER_CONFIG", "/etc/salt/master")

from salt.netapi.rest_cherrypy.wsgi import application


class ThreadingWSGIServer(ThreadingMixIn, WSGIServer):
    daemon_threads = True
    allow_reuse_address = True


class LoggingWSGIRequestHandler(WSGIRequestHandler):
    def log_message(self, format: str, *args: object) -> None:  # noqa: A003
        sys.stderr.write(f"[salt-api:wsgi] {self.address_string()} - {format % args}\n")


def main() -> int:
    host = os.environ.get("SALT_REST_HOST", "127.0.0.1")
    port = int(os.environ.get("SALT_REST_PORT", "3333"))

    with make_server(
        host,
        port,
        application,
        server_class=ThreadingWSGIServer,
        handler_class=LoggingWSGIRequestHandler,
    ) as httpd:
        print(f"[salt-api:wsgi] serving Salt REST API on http://{host}:{port}", flush=True)
        httpd.serve_forever()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
