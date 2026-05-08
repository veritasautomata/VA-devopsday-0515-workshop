#!/usr/bin/env python3
"""
Serves stats-dashboard.html and proxies /stats and /health to pipelock.
Avoids browser CORS errors — everything comes from one origin.

Usage:
    python3 serve-dashboard.py          # port 9999, pipelock on 127.0.0.1:8888
    python3 serve-dashboard.py 8080     # custom port
"""

import http.server
import urllib.request
import urllib.error
import sys
import os

PIPELOCK = "http://127.0.0.1:8888"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9999

PROXY_PATHS = {"/stats", "/health"}

class Handler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path in PROXY_PATHS:
            self._proxy(PIPELOCK + self.path)
        else:
            # Rewrite bare / to the dashboard file
            if self.path == "/":
                self.path = "/stats-dashboard.html"
            super().do_GET()

    def _proxy(self, url):
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                body = resp.read()
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.URLError as e:
            msg = str(e).encode()
            self.send_response(502)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(msg)))
            self.end_headers()
            self.wfile.write(msg)

    def log_message(self, fmt, *args):
        # Suppress noisy per-request logs; only show startup line
        pass

os.chdir(os.path.dirname(os.path.abspath(__file__)))
print(f"Dashboard → http://localhost:{PORT}/")
print(f"Proxying  → {PIPELOCK}/stats  and  {PIPELOCK}/health")
print("Ctrl-C to stop.")
http.server.HTTPServer(("", PORT), Handler).serve_forever()
