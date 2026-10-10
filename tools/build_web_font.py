"""Subset Web UI glyphs without changing the native font or glyph outlines.

The full font is a deferred fallback for dynamic text. Both generated files are
imported normally; the Web PCK postprocessor replaces only the original font's
exported payload, preserving all authored scene/resource references.
"""
from pathlib import Path
import hashlib
import json
import shutil
from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
SOURCE = GAME / "assets/fonts/NotoSansTC.ttf"
DEST = GAME / "assets/fonts/web"

def build():
    chars = set(range(32, 127)) | {0x3000, 0xfffd}
    for folder in ("scripts", "scenes", "data", "tools", "generated"):
        for file in (GAME / folder).rglob("*"):
            if file.suffix in (".gd", ".json", ".tscn", ".tres"):
                chars.update(map(ord, file.read_text(encoding="utf-8")))
    font = TTFont(SOURCE, recalcTimestamp=False)
    cmap = font.getBestCmap()
    selected = chars & set(cmap)
    options = subset.Options()
    options.recalc_timestamp = False
    options.layout_features = ["*"]
    options.name_IDs = ["*"]
    options.name_legacy = True
    options.name_languages = ["*"]
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=selected)
    worker.subset(font)
    DEST.mkdir(parents=True, exist_ok=True)
    target = DEST / "LittleWorldTC.ttf"
    font.save(target)
    check = TTFont(target)
    assert set(check.getBestCmap()) >= selected
    # All variation axes, glyph outlines, metrics and layout rules are kept by
    # fontTools; retain the source licence next to the original font.
    shutil.copyfile(SOURCE, DEST / "NotoSansTC-full.ttf")
    supported = sorted(cmap)
    ranges = []
    for code in supported:
        if ranges and code == ranges[-1][1] + 1:
            ranges[-1][1] = code
        else:
            ranges.append([code, code])
    report = {"source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
              "source_bytes": SOURCE.stat().st_size, "subset_bytes": target.stat().st_size,
              "source_glyphs": len(cmap), "subset_glyphs": len(selected),
              "supported_ranges": ranges}
    (GAME / "data/web_font.json").write_text(json.dumps(report, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    print(json.dumps({k:v for k,v in report.items() if k != "supported_ranges"}))

if __name__ == "__main__":
    build()
