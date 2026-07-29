#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import urlparse


OUTPUT_DIR = Path(__file__).resolve().parents[2] / "docs" / "screenshots" / "5x-test"
MAX_BYTES = 20 * 1024 * 1024


class Handler(BaseHTTPRequestHandler):
    def do_PUT(self):
        length = int(self.headers.get("Content-Length", "0"))
        name = Path(urlparse(self.path).path).name
        valid = name.replace("-", "").replace("_", "").replace(".", "").isalnum()
        if not name.endswith(".png") or not valid:
            self.send_error(400, "invalid PNG name")
            return
        if length <= 0 or length > MAX_BYTES:
            self.send_error(413, "invalid upload size")
            return

        OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
        (OUTPUT_DIR / name).write_bytes(self.rfile.read(length))
        self.send_response(201)
        self.end_headers()

    def log_message(self, *_args):
        pass


HTTPServer(("192.168.2.20", 18103), Handler).serve_forever()
