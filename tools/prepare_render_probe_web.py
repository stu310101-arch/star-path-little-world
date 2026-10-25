"""Local-only Web renderer probe using unchanged exported resource payloads.

Combines an existing release's deferred packs so downloads cannot disturb the
measurement. Adds an explicitly selected test script, never alters that release.
No production loader, service worker, Firebase credentials or account storage.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import shutil
import struct

from split_web_packs import read_pack, write_pack

ROOT = Path(__file__).resolve().parents[1]

def with_probe_scene(payload: bytes, scene: str) -> bytes:
    """Change only the fixture's main scene using Godot 4.7 ECFG/Variant format."""
    if payload[:4] != b"ECFG":
        raise ValueError("Unknown project.binary format")
    cursor, result, changed = 8, bytearray(payload[:8]), 0
    for _ in range(struct.unpack_from("<I", payload, 4)[0]):
        size, = struct.unpack_from("<I", payload, cursor)
        key = payload[cursor + 4:cursor + 4 + size]
        result += payload[cursor:cursor + 4 + size]
        cursor += 4 + size
        length, = struct.unpack_from("<I", payload, cursor)
        value = payload[cursor + 4:cursor + 4 + length]
        cursor += 4 + length
        if key == b"application/run/main_scene":
            if struct.unpack_from("<I", value)[0] != 4:
                raise ValueError("Main scene is not a String Variant")
            encoded = ("res://" + scene).encode()
            value = struct.pack("<II", 4, len(encoded)) + encoded + bytes(-len(encoded) % 4)
            changed += 1
        result += struct.pack("<I", len(value)) + value
    if cursor != len(payload) or changed != 1:
        raise ValueError("Expected exactly one main scene in project.binary")
    return bytes(result)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "build/web")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--script", required=True, help="game-relative test script")
    parser.add_argument("--scene", help="Optional scene for a Node-based probe")
    parser.add_argument("--overlay", action="append", default=[],
                        help="game-relative source script to replace in this fixture only")
    parser.add_argument("--arguments", nargs="*", default=[])
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    output = args.output.resolve()
    if not output.is_relative_to(ROOT / "build") or output == source:
        raise ValueError("Probe output must be a separate folder inside build/")
    output.mkdir(parents=True, exist_ok=True)
    pack = read_pack(source / "index.pck")
    entries = dict(pack.entries)
    manifest = json.loads(bytes(entries["data/web_packs.json"]))
    for info in manifest["packs"].values():
        deferred = read_pack(source / info["url"])
        for name, payload in deferred.entries.items():
            if name in entries and entries[name] != payload:
                raise ValueError(f"Conflicting resource in deferred pack: {name}")
            entries[name] = payload
    # Every resource is mounted from boot; skip production network scheduling.
    entries.pop("data/web_packs.json")
    if args.scene:
        entries["project.binary"] = with_probe_scene(bytes(entries["project.binary"]), args.scene)
    scripts = [args.script, "tests/startup_fixture.gd", *args.overlay]
    if args.scene:
        scripts.append(args.scene)
    for relative in scripts:
        file = (ROOT / "game" / relative).resolve(strict=True)
        if not file.is_relative_to(ROOT / "game") or file.suffix not in (".gd", ".tscn"):
            raise ValueError(f"Not a project script or test scene: {relative}")
        name = file.relative_to(ROOT / "game").as_posix()
        entries.pop(name + ".remap", None)
        entries.pop(name.removesuffix(".gd") + ".gdc", None)
        entries[name] = file.read_bytes()
    result = write_pack(output / "index.pck", entries, pack.engine)
    for name in ("index.js", "index.wasm", "index.audio.worklet.js",
                 "index.audio.position.worklet.js", "index.account.js", "index.touch.js"):
        shutil.copyfile(source / name, output / name)
    config = {
        "args": ([] if args.scene else
                 ["--script", "res://" + args.script]) + ["--", *args.arguments],
        "canvasResizePolicy": 0, "executable": "index", "focusCanvas": True,
        "fileSizes": {"index.pck": result["bytes"],
                      "index.wasm": (output / "index.wasm").stat().st_size},
    }
    html = """<!doctype html><html lang="zh-Hant"><meta charset="utf-8">
<title>星途：固定畫質效能診斷（本機）</title>
<style>body{margin:0;background:#101820;color:#fff;font:16px sans-serif}
canvas{display:block;width:1280px;height:800px}pre{white-space:pre-wrap}</style>
<canvas id="canvas" width="1280" height="800" tabindex="0"></canvas>
<button id="start" style="position:fixed;left:32px;top:32px;padding:20px;font-size:24px">開始固定畫質測試</button>
<pre id="status">正在載入固定場景；測試暫時隱藏個別類別以診斷成本，並非正式畫面。</pre>
<script src="index.js"></script><script src="index.account.js"></script>
<script src="index.touch.js"></script><script>
const config=CONFIG;config.canvas=document.getElementById('canvas');
document.getElementById('start').onclick=()=>{
document.getElementById('start').remove();config.canvas.focus();
new Engine(config).startGame().catch(e=>document.getElementById('status').textContent=String(e));
};
</script></html>""".replace("CONFIG", json.dumps(config))
    (output / "index.html").write_text(html, encoding="utf-8")
    (output / "probe-build.json").write_text(json.dumps({
        "source": str(source), "scripts": scripts, "pack": result,
        "args": config["args"], "fixture_only": True,
    }, indent=2), encoding="utf-8")
    print(json.dumps({"output": str(output), "bytes": result["bytes"]}))


if __name__ == "__main__":
    main()
