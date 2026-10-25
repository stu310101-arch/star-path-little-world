"""Local-only real-tab visibility QA; does not modify the release directory.

Open /?performance&background-qa and click the test link. A normal target=_blank
navigation hides the game tab; closing that tab resumes it. No synthetic
visibility events or game APIs are used.
"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
import argparse


class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        url = urlsplit(self.path)
        if url.path == "/qa-hide.html":
            body = """<!doctype html><html lang="zh-Hant"><meta charset="utf-8">
<title>背景繪圖驗證</title><body style="font:24px sans-serif;padding:4rem">
<h1>遊戲目前位於另一個分頁</h1>
<p>這是本機驗證頁，不會包含在正式發布。</p>
<button onclick="window.close()" style="font:inherit;padding:1rem">關閉測試頁，回到遊戲</button>
</body></html>""".encode()
        elif url.path == "/" and "background-qa" in parse_qs(url.query, keep_blank_values=True):
            body = (Path(self.directory) / "index.html").read_bytes()
            body = body.replace(b"</body>", """<a href="/qa-hide.html" target="_blank"
style="position:fixed;top:0;left:45%;z-index:99999;background:white;color:black;padding:8px">
切換到背景測試分頁</a></body>""".encode())
        else:
            return super().do_GET()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8770)
    args = parser.parse_args()
    directory = args.directory.resolve(strict=True)
    ThreadingHTTPServer(("127.0.0.1", args.port),
                        lambda *a, **kw: Handler(*a, directory=str(directory), **kw)).serve_forever()
