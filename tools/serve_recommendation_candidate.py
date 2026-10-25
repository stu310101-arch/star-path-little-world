"""Serve a local game candidate and account host against local Firebase emulators.

No production configuration is written or used. Start the demo-starpath-tests
Auth/Firestore emulators first. This preview binds only to localhost.
"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, unquote
from urllib.request import urlopen
import argparse
import json
import mimetypes

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--web', type=Path, default=ROOT / '_site')
    parser.add_argument('--host', type=Path, default=ROOT / 'admissions-site/out')
    parser.add_argument('--port', type=int, default=4317)
    args = parser.parse_args()
    web, host = args.web.resolve(strict=True), args.host.resolve(strict=True)
    with urlopen('http://127.0.0.1:4400/emulators', timeout=5) as response:
        services = json.load(response)
    if any(services.get(name, {}).get('port') != port for name, port in (('auth',9099),('firestore',8080))):
        raise RuntimeError('Start demo-starpath-tests Auth/Firestore emulators on 9099/8080 first.')
    if not (host/'host/index.html').is_file():
        raise RuntimeError('Build admissions-site with NEXT_PUBLIC_BASE_PATH=/admissions first.')

    class Handler(SimpleHTTPRequestHandler):
        def do_GET(self):
            pathname = unquote(urlsplit(self.path).path)
            if pathname == '/admissions/firebase-config.json':
                payload = json.dumps({'apiKey':'demo-key','authDomain':'localhost','projectId':'demo-starpath-tests','appId':'1:123:web:demo','useEmulators':True}).encode()
                self.send_response(200)
                self.send_header('Content-Type','application/json')
                self.send_header('Cache-Control','no-store')
                self.send_header('Content-Length',str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)
                return
            base, relative = (host,pathname[len('/admissions/'):]) if pathname.startswith('/admissions/') else (web,pathname.lstrip('/'))
            target = (base/relative).resolve()
            if not target.is_relative_to(base):
                self.send_error(403)
                return
            if target.is_dir():
                target /= 'index.html'
            if not target.is_file():
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type',mimetypes.guess_type(str(target))[0] or 'application/octet-stream')
            self.send_header('Content-Length',str(target.stat().st_size))
            self.send_header('Cache-Control','no-store')
            self.end_headers()
            with target.open('rb') as source:
                self.copyfile(source,self.wfile)

    mimetypes.add_type('application/wasm','.wasm')
    print(f'Local recommendation candidate: http://127.0.0.1:{args.port}/ ; demo accounts only',flush=True)
    ThreadingHTTPServer(('127.0.0.1',args.port),Handler).serve_forever()


if __name__ == '__main__':
    main()
