#!/usr/bin/env python3
# A tiny stand-in for the Pi-hole 6 API, for tests/pihole.pl. Answers from a
# JSON file of path -> reply, read again on every request so the test can
# change it; unknown GET paths get an empty object.
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port, replies = int(sys.argv[1]), sys.argv[2]

class H(BaseHTTPRequestHandler):
    def reply(self):
        with open(replies) as f:
            data = json.load(f)
        path = self.path.split("?")[0]
        body = json.dumps(data.get(path, {})).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def do_GET(self):
        self.reply()
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length") or 0))
        self.reply()
    def log_message(self, *a):
        pass

HTTPServer(("127.0.0.1", port), H).serve_forever()
