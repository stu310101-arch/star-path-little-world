"""Delivery build failure modes and byte-identical fallback proof, using tiny files."""
import gzip
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from prepare_web_delivery import BACKGROUND_BUFFER_LIMIT, LOADER_SHA256, OPTIMIZED_LOADER_SHA256, ROOT, prepare, verify, verify_background_budget


class BootDeliveryBuildTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.loader = b"fixture loader, exact version pinned"
        (self.root / "index.js").write_bytes(self.loader)
        self.loader_hash = hashlib.sha256(self.loader).hexdigest()
        self.pck = struct.pack("<5I", 0x43504447, 4, 4, 7, 2) + b"pck fixture " * 200
        (self.root / "index.pck").write_bytes(self.pck)
        (self.root / "index.wasm").write_bytes(b"wasm" * 1000)
        (self.root / "index.packs.json").write_text(json.dumps({"version": 1, "packs": {"avatar": {"bytes": 4000, "url": "packs/avatar.pck"}}}), encoding="utf-8")
        config = {"executable": "index", "fileSizes": {"index.pck": len(self.pck), "index.wasm": 4000}}
        html = '<script src="index.js"></script>\n<script>const GODOT_CONFIG = ' + json.dumps(config) + ";\nconst GODOT_THREADS_ENABLED = false;\nengine.startGame({'onProgress': function (current, total) {}});</script>"
        (self.root / "index.html").write_text(html, encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def build(self):
        verify_background_budget(self.root)
        packs = json.loads((self.root / "index.packs.json").read_text())["packs"]
        for pack in packs.values():
            target = self.root / pack["url"]
            target.parent.mkdir(parents=True, exist_ok=True)
            if not target.exists():
                target.write_bytes(b"a" * pack["bytes"])
        return prepare(self.root, self.loader_hash)

    def test_interior_is_not_startup_and_cannot_be_required_by_startup(self):
        manifest = {"version":1,"packs":{"outside":{"bytes":4000,"url":"packs/outside.pck"},
                     "training_room":{"bytes":4096,"url":"packs/room.pck","startup":False}}}
        target = self.root / "index.packs.json"
        target.write_text(json.dumps(manifest), encoding="utf-8")
        self.assertEqual(verify_background_budget(self.root), 4000)
        self.build()
        self.assertNotIn("transport.enqueue(", (self.root / "index.html").read_text(encoding="utf-8"))
        manifest["packs"]["outside"]["dependencies"] = ["training_room"]
        target.write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "on-demand"):
            verify_background_budget(self.root)

    def test_roundtrip_deterministic_and_idempotent(self):
        manifest = self.build()
        self.assertEqual(len(verify(self.root)), 6)
        for name, item in manifest["files"].items():
            self.assertEqual(gzip.decompress((self.root / item["url"]).read_bytes()), (self.root / name).read_bytes())
        self.assertEqual(self.build(), manifest)
        html = (self.root / "index.html").read_text(encoding="utf-8")
        self.assertEqual(html.count('src="index.delivery.js"'), 1)
        self.assertEqual(html.count('src="index.background.js"'), 1)
        self.assertEqual(html.count('window.LittleWorldBootDelivery.install'), 1)
        self.assertEqual(html.count('startLittleWorldBackgroundDownloads();'), 1)
        self.assertEqual(html.count('if (!LITTLE_WORLD_BOOT_STATUS.engineProgress(current, total)) return;'), 1)
        self.assertLess(html.index('startLittleWorldBackgroundDownloads();'), html.index('engine.startGame({'))
        self.assertEqual((self.root / "index.pck").read_bytes(), self.pck)

    def test_unknown_loader_and_engine_fail_before_writing(self):
        with self.assertRaisesRegex(ValueError, "Unknown Web loader"):
            prepare(self.root)
        self.assertFalse((self.root / "index.delivery.json").exists())
        data = bytearray(self.pck)
        struct.pack_into("<I", data, 16, 3)
        (self.root / "index.pck").write_bytes(data)
        with self.assertRaisesRegex(ValueError, "4.7.2"):
            self.build()

    def test_pinned_presentation_query_is_the_only_loader_change_and_is_idempotent(self):
        original = (ROOT / "deploy/github-pages/files/index.js").read_bytes()
        if hashlib.sha256(original).hexdigest() == OPTIMIZED_LOADER_SHA256:
            original = original.replace(b"var prevScissorTest=gl.isEnabled(3089);", b"var prevScissorTest=gl.getParameter(3089);")
        self.assertEqual(hashlib.sha256(original).hexdigest(), LOADER_SHA256)
        (self.root / "index.js").write_bytes(original)
        self.loader_hash = LOADER_SHA256
        first = self.build()
        optimized = (self.root / "index.js").read_bytes()
        self.assertEqual(hashlib.sha256(optimized).hexdigest(), OPTIMIZED_LOADER_SHA256)
        self.assertEqual(optimized.replace(b"var prevScissorTest=gl.isEnabled(3089);", b"var prevScissorTest=gl.getParameter(3089);"), original)
        self.assertEqual(self.build(), first)
        verify(self.root)

    def test_corrupt_gzip_and_inline_manifest_are_rejected(self):
        manifest = self.build()
        gz = self.root / manifest["files"]["index.pck"]["url"]
        gz.write_bytes(gz.read_bytes()[:-4])
        with self.assertRaisesRegex(ValueError, "Compressed boot file"):
            verify(self.root)
        self.build()
        html = self.root / "index.html"
        html.write_text(html.read_text(encoding="utf-8").replace('"version":1', '"version":2'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Inline delivery"):
            verify(self.root)

    def test_cleanup_preserves_unowned_files_and_rejects_unsafe_previous_path(self):
        manifest = self.build()
        unowned = self.root / "index.boot.user-note.gz"
        unowned.write_bytes(b"keep")
        # Change payload without changing size to produce a new owned gzip URL.
        (self.root / "index.wasm").write_bytes(b"new!" * 1000)
        self.build()
        self.assertFalse((self.root / manifest["files"]["index.wasm"]["url"]).exists())
        self.assertEqual(unowned.read_bytes(), b"keep")
        manifest["files"]["index.pck"]["url"] = "../outside.gz"
        (self.root / "index.delivery.json").write_text(json.dumps(manifest), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "Unsafe previous"):
            self.build()

    def test_all_startup_pack_sum_must_fit_background_budget_at_build_and_stamp(self):
        manifest = self.root / "index.packs.json"
        with patch("prepare_web_delivery.BACKGROUND_BUFFER_LIMIT", 128):
            manifest.write_text(json.dumps({"version": 1, "packs": {"a": {"bytes": 128, "url": "packs/a.pck"}}}), encoding="utf-8")
            self.build()
            verify(self.root)
            manifest.write_text(json.dumps({"version": 1, "packs": {"a": {"bytes": 128, "url": "packs/a.pck"}, "b": {"bytes": 1, "url": "packs/b.pck"}}}), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "background buffer limit"):
                self.build()
            with self.assertRaisesRegex(ValueError, "background buffer limit"):
                verify(self.root)

    def test_background_manifest_mismatch_or_late_queue_is_rejected(self):
        self.build()
        html = self.root / "index.html"
        text = html.read_text(encoding="utf-8")
        before, after = text.split("const LITTLE_WORLD_BACKGROUND_PACKS = ", 1)
        html.write_text(before + "const LITTLE_WORLD_BACKGROUND_PACKS = " + after.replace('"packs/avatar.pck"', '"packs/other.pck"'), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "background metadata"):
            verify(self.root)
        html.write_text(text.replace('startLittleWorldBackgroundDownloads();', ''), encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "before engine startup"):
            verify(self.root)


if __name__ == "__main__":
    unittest.main()
