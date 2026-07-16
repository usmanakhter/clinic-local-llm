#!/usr/bin/env python3
"""
Tiny CORS proxy so Flutter web (localhost:8080) can call Ollama (11434).

Usage:
    ollama serve
    python tools/ollama_cors_proxy.py
    # App Notes tab uses http://127.0.0.1:8765 by default on web
"""

from __future__ import annotations

import http.client
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTEN = ("127.0.0.1", 8765)
UPSTREAM_HOST = "127.0.0.1"
UPSTREAM_PORT = 11434


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        print(f"[proxy] {self.address_string()} {fmt % args}")

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers", "Content-Type, Authorization"
        )

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        self._proxy("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._proxy("POST")

    def _proxy(self, method: str) -> None:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else None
        conn = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=120)
        headers = {"Content-Type": self.headers.get("Content-Type", "application/json")}
        try:
            conn.request(method, self.path, body=body, headers=headers)
            resp = conn.getresponse()
            data = resp.read()
            self.send_response(resp.status)
            self._cors()
            ctype = resp.getheader("Content-Type", "application/json")
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:  # noqa: BLE001
            payload = json.dumps({"error": str(e)}).encode("utf-8")
            self.send_response(502)
            self._cors()
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        finally:
            conn.close()


def main() -> None:
    server = ThreadingHTTPServer(LISTEN, Handler)
    print(f"Ollama CORS proxy on http://{LISTEN[0]}:{LISTEN[1]} -> :{UPSTREAM_PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
