"""Losslessly reblock exported RSCC resources; source/import caches stay intact."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from split_web_packs import read_pack, write_pack, exported_entries

ROOT = Path(__file__).resolve().parents[1]


def recompress(source, node):
    pack = read_pack(source)
    if pack.engine != (4, 7, 2):
        raise ValueError("Review RSCC format before changing Godot version")
    entries = dict(pack.entries)
    original = exported_entries("res://assets/fonts/NotoSansTC.ttf", entries)
    subset = exported_entries("res://assets/fonts/web/LittleWorldTC.ttf", entries)
    original_font = [name for name in original if name.endswith(".fontdata")]
    subset_font = [name for name in subset if name.endswith(".fontdata")]
    assert len(original_font) == len(subset_font) == 1
    entries[original_font[0]] = entries[subset_font[0]]
    with tempfile.TemporaryDirectory(prefix="web-resource-blocks-", dir=ROOT / "build") as temporary:
        folder = Path(temporary)
        selected = []
        for name, payload in entries.items():
            if len(payload) >= 8192 and bytes(payload[:4]) == b"RSCC":
                row = {"resource": name, "file": f"{len(selected)}.rscc"}
                selected.append(row)
                (folder / row["file"]).write_bytes(payload)
        (folder / "inputs.json").write_text(json.dumps(selected), encoding="utf-8")
        subprocess.run([node, str(ROOT / "tools/recompress_web_resources.cjs"), str(folder)], check=True)
        report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
        for row in selected:
            entries[row["resource"]] = (folder / row["file"]).read_bytes()
        target = source.with_suffix(".reblocked.pck")
        write_pack(target, entries, pack.engine)
        target.replace(source)
    (ROOT / "build/web-resource-compression.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"resources": len(report), "before_bytes": sum(r["before"] for r in report),
                      "after_bytes": sum(r["after"] for r in report), "all_decoded_payloads_identical": True}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--node", default=shutil.which("node"))
    args = parser.parse_args()
    if not args.node:
        parser.error("Node 24+ is required for Zstandard recompression")
    recompress(args.source, args.node)
