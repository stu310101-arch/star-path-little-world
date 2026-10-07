"""Add optional application-gzip boot delivery without modifying Godot's loader.

Run after splitting the PCK and before stamping/packaging. Originals remain as
fallbacks. Browser gzip decompression validates its footer and decoded SHA-256;
it adds decode/hash work and buffers a complete file before Godot consumes it.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
LOADER_SHA256 = "33c94cb3175f3333b82e2a3be5e8e86f77986f0aa2042b1631f6367a4e5bb6ba"
MANIFEST = "index.delivery.json"
SCRIPT = "index.delivery.js"
BACKGROUND_SCRIPT = "index.background.js"
CONFIG_START = "// LITTLE_WORLD_BOOT_DELIVERY_BEGIN"
CONFIG_END = "// LITTLE_WORLD_BOOT_DELIVERY_END"
BACKGROUND_BUFFER_LIMIT = 128 * 1024 * 1024


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def verify_background_budget(folder: Path) -> int:
    """All queued files must fit while a hidden page cannot consume Godot frames."""
    packs = json.loads((folder / "index.packs.json").read_text(encoding="utf-8"))
    if packs.get("version") != 1 or not isinstance(packs.get("packs"), dict):
        raise ValueError("Missing or invalid deferred pack manifest")
    sizes = [item.get("bytes") for item in packs["packs"].values()]
    if any(type(size) is not int or size <= 0 for size in sizes):
        raise ValueError("Invalid deferred pack size")
    total = sum(sizes)
    if total > BACKGROUND_BUFFER_LIMIT:
        raise ValueError(f"All startup packs need {total} bytes; background buffer limit is {BACKGROUND_BUFFER_LIMIT}. Review scheduling before increasing it.")
    return total


def prepare(folder: Path, expected_loader_sha256: str = LOADER_SHA256) -> dict:
    folder = folder.resolve()
    verify_background_budget(folder)
    loader_hash = digest((folder / "index.js").read_bytes())
    if loader_hash != expected_loader_sha256:
        raise ValueError("Unknown Web loader; review the boot adapter for this Godot/template version")
    with (folder / "index.pck").open("rb") as stream:
        header = stream.read(20)
    if len(header) != 20 or struct.unpack("<5I", header) != (0x43504447, 4, 4, 7, 2):
        raise ValueError("Boot delivery expects a Godot 4.7.2 format-4 PCK")
    html_path = folder / "index.html"
    html = html_path.read_text(encoding="utf-8")
    match = re.search(r"const GODOT_CONFIG\s*=\s*(\{[^\n]+\});", html)
    if not match:
        raise ValueError("Missing Godot configuration")
    config = json.loads(match[1])
    if config.get("executable") != "index" or config.get("experimentalVK", False) or config.get("gdextensionLibs", []):
        raise ValueError("Unexpected Web export configuration")
    if not re.search(r"const GODOT_THREADS_ENABLED\s*=\s*false;", html):
        raise ValueError("Boot delivery expects the reviewed single-threaded Web export")
    previous_path = folder / MANIFEST
    previous = json.loads(previous_path.read_text(encoding="utf-8")) if previous_path.exists() else {}
    old_urls = {row["url"] for row in previous.get("files", {}).values()}
    if any(not re.fullmatch(r"index\.boot\.[a-f0-9]{16}\.(pck|wasm)\.gz", name) for name in old_urls):
        raise ValueError("Unsafe previous gzip path; refusing cleanup")
    manifest = {"version": 1, "engine_version": "4.7.2", "loader_sha256": loader_hash, "files": {}}
    pack_manifest = json.loads((folder / "index.packs.json").read_text(encoding="utf-8"))
    background_manifest = {"version": 1, "packs": pack_manifest["packs"]}
    outputs = {}
    for name in ("index.pck", "index.wasm"):
        original = (folder / name).read_bytes()
        if len(original) != config["fileSizes"][name]:
            raise ValueError(f"HTML fileSizes mismatch: {name}")
        compressed = gzip.compress(original, compresslevel=6, mtime=0)
        sha = digest(compressed)
        url = f"index.boot.{sha[:16]}.{name.split('.')[-1]}.gz"
        outputs[url] = compressed
        manifest["files"][name] = {"url": url, "bytes": len(original), "sha256": digest(original),
                                   "compressed_bytes": len(compressed), "compressed_sha256": sha}
    html = re.sub(r"\n?" + re.escape(CONFIG_START) + r".*?" + re.escape(CONFIG_END) + r"\n?", "\n", html, flags=re.S)
    html = re.sub(r"[\t ]*startLittleWorldBackgroundDownloads\(\);\n?", "", html)
    for call in ("LITTLE_WORLD_BOOT_STATUS.engineProgress(current, total);",
                 "if (!LITTLE_WORLD_BOOT_STATUS.engineProgress(current, total)) return;"):
        html = re.sub(r"[\t ]*" + re.escape(call) + r"\n?", "", html)
    for name in (SCRIPT, BACKGROUND_SCRIPT):
        html = re.sub(r"[\t ]*" + re.escape(f'<script src="{name}"></script>') + r"\n?", "", html)
    script_anchor = '<script src="index.js"></script>'
    if html.count(script_anchor) != 1:
        raise ValueError("Unknown HTML loader anchor")
    html = html.replace(script_anchor, script_anchor + f'\n\t\t<script src="{SCRIPT}"></script>\n\t\t<script src="{BACKGROUND_SCRIPT}"></script>')
    start_anchor = "engine.startGame({"
    if html.count(start_anchor) != 1:
        raise ValueError("Unknown HTML engine startup anchor")
    # Run only in the supported-browser branch, before starting any engine work.
    html = html.replace(start_anchor, "startLittleWorldBackgroundDownloads();\n\t\t" + start_anchor)
    progress_anchor = "'onProgress': function (current, total) {"
    if html.count(progress_anchor) != 1:
        raise ValueError("Unknown HTML progress callback anchor")
    html = html.replace(progress_anchor, progress_anchor + "\n\t\t\t\tif (!LITTLE_WORLD_BOOT_STATUS.engineProgress(current, total)) return;")
    match = re.search(r"const GODOT_CONFIG\s*=\s*(\{[^\n]+\});", html)
    injection = ("\n" + CONFIG_START + "\nconst LITTLE_WORLD_BOOT_DELIVERY = "
                 + json.dumps(manifest, separators=(",", ":"))
                 + ";\nwindow.LittleWorldBootDelivery.install(GODOT_CONFIG, LITTLE_WORLD_BOOT_DELIVERY);\n"
                 + "const LITTLE_WORLD_BOOT_STATUS = window.LittleWorldBootDelivery.attachStatusUI();\n"
                 + "const LITTLE_WORLD_BACKGROUND_PACKS = " + json.dumps(background_manifest, separators=(",", ":")) + ";\n"
                 + "function startLittleWorldBackgroundDownloads() {\n"
                 + "  const transport = window.LittleWorldBackgroundPacks;\n"
                 + "  transport.configure(new URL('.', location.href).href);\n"
                 + "  for (const [id, pack] of Object.entries(LITTLE_WORLD_BACKGROUND_PACKS.packs)) {\n"
                 + "    transport.enqueue(id, pack.url, pack.bytes, id === 'avatar' ? 20 : 0);\n"
                 + "  }\n}\n"
                 + CONFIG_END + "\n")
    html = html[:match.end()] + injection + html[match.end():]
    # All validation above completes before replacing release files.
    for name, payload in outputs.items():
        (folder / name).write_bytes(payload)
    (folder / SCRIPT).write_bytes((ROOT / "tools/web_boot_delivery.js").read_bytes())
    (folder / BACKGROUND_SCRIPT).write_bytes((ROOT / "tools/web_background_packs.js").read_bytes())
    previous_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    html_path.write_text(html, encoding="utf-8", newline="\n")
    for name in old_urls - set(outputs):
        obsolete = (folder / name).resolve()
        if not obsolete.is_relative_to(folder):
            raise ValueError("Gzip path escapes export")
        obsolete.unlink(missing_ok=True)
    return manifest


def verify(folder: Path) -> list[str]:
    """Validate originals, gzip bytes, decompression, loader and inline manifest."""
    folder = folder.resolve()
    verify_background_budget(folder)
    manifest = json.loads((folder / MANIFEST).read_text(encoding="utf-8"))
    if manifest.get("version") != 1 or manifest.get("engine_version") != "4.7.2" or manifest["loader_sha256"] != digest((folder / "index.js").read_bytes()):
        raise ValueError("Boot delivery loader/version mismatch")
    if set(manifest["files"]) != {"index.pck", "index.wasm"}:
        raise ValueError("Unexpected boot delivery file set")
    html = (folder / "index.html").read_text(encoding="utf-8")
    inline = re.search(r"const LITTLE_WORLD_BOOT_DELIVERY = (\{[^\n]+\});", html)
    if not inline or json.loads(inline[1]) != manifest:
        raise ValueError("Inline delivery metadata differs from manifest")
    pack_manifest = json.loads((folder / "index.packs.json").read_text(encoding="utf-8"))
    background = re.search(r"const LITTLE_WORLD_BACKGROUND_PACKS = (\{[^\n]+\});", html)
    if not background or json.loads(background[1]) != {"version": 1, "packs": pack_manifest["packs"]}:
        raise ValueError("Inline background metadata differs from pack manifest")
    if html.count("startLittleWorldBackgroundDownloads();") != 1 or html.index("startLittleWorldBackgroundDownloads();") > html.index("engine.startGame({"):
        raise ValueError("Background downloads must begin before engine startup")
    if html.count("window.LittleWorldBootDelivery.attachStatusUI();") != 1 or html.count("if (!LITTLE_WORLD_BOOT_STATUS.engineProgress(current, total)) return;") != 1:
        raise ValueError("Boot status UI is not connected to engine progress")
    if (folder / SCRIPT).read_bytes() != (ROOT / "tools/web_boot_delivery.js").read_bytes():
        raise ValueError("Boot delivery script differs from source")
    if (folder / BACKGROUND_SCRIPT).read_bytes() != (ROOT / "tools/web_background_packs.js").read_bytes():
        raise ValueError("Background pack script differs from source")
    names = [MANIFEST, SCRIPT, BACKGROUND_SCRIPT]
    for name, item in manifest["files"].items():
        url = item["url"]
        if not re.fullmatch(r"index\.boot\.[a-f0-9]{16}\.(pck|wasm)\.gz", url):
            raise ValueError("Unsafe gzip URL")
        original = (folder / name).read_bytes()
        compressed = (folder / url).read_bytes()
        if len(original) != item["bytes"] or digest(original) != item["sha256"]:
            raise ValueError(f"Original boot file differs: {name}")
        if len(compressed) != item["compressed_bytes"] or digest(compressed) != item["compressed_sha256"] or gzip.decompress(compressed) != original:
            raise ValueError(f"Compressed boot file differs: {url}")
        names.append(url)
    return names


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-dir", type=Path, default=ROOT / "build/web")
    args = parser.parse_args()
    result = prepare(args.web_dir)
    verify(args.web_dir)
    print(json.dumps(result, indent=2))
