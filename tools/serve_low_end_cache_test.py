"""Localhost cache test fixture; does not change the game or production hosting.

Cold measurements use a fresh Chrome context. Revisit must prove HTTP cache hits
in CDP, rather than assuming that any reload is a cached reload.
"""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Handler(SimpleHTTPRequestHandler):
    def end_headers(self):
        path = self.path.split("?", 1)[0]
        self.send_header("Cache-Control", "no-cache" if path.endswith((".html", ".json"))
                         else "private, max-age=3600")
        super().end_headers()


if __name__ == "__main__":
    directory = Path(__file__).resolve().parents[1]
    ThreadingHTTPServer(("127.0.0.1", 8952), partial(Handler, directory=str(directory))).serve_forever()
