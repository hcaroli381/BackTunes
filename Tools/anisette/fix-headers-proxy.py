#!/usr/bin/env python3
"""Tiny reverse proxy in front of omnisette-server.

AltServer-Linux (2022, vibe.d HTTP client) refuses to parse the anisette
JSON because omnisette-server 0.2.0 replies with Content-Type: text/plain.
This proxy just fixes the Content-Type on JSON responses.

Listens on 127.0.0.1:6969  ->  forwards to omnisette on 127.0.0.1:7969.
"""

import http.server
import urllib.request

UPSTREAM = "http://127.0.0.1:7969"


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _proxy(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else None
        req = urllib.request.Request(UPSTREAM + self.path, data=body, method=self.command)
        for key in ("Content-Type", "Accept"):
            if self.headers.get(key):
                req.add_header(key, self.headers[key])
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                payload = resp.read()
                ctype = resp.headers.get("Content-Type", "application/json")
        except urllib.error.HTTPError as err:
            payload = err.read()
            ctype = err.headers.get("Content-Type", "text/plain")
        if ctype.startswith("text/plain") and payload[:1] == b"{":
            ctype = "application/json"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = _proxy

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 6969), Handler)
    print("anisette content-type proxy on 127.0.0.1:6969 -> 7969", flush=True)
    server.serve_forever()
