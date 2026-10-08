"""Check copied source, idempotence, integrity and final Pages inclusion."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

from package_training_games import ADAPTER, MANIFEST, ROOT, SCRIPT, SOURCE, package, verify


class TrainingGamePackageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name) / "web"
        self.folder.mkdir()
        (self.folder / "index.html").write_text('<html><script src="index.js"></script></html>', encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def test_copy_is_exact_and_injection_idempotent(self):
        first = package(self.folder)
        html = (self.folder / "index.html").read_bytes()
        self.assertEqual(package(self.folder), first)
        self.assertEqual((self.folder / "index.html").read_bytes(), html)
        self.assertEqual((self.folder / "games/go/index.html").read_bytes(), (SOURCE / "go/index.html").read_bytes())
        self.assertEqual((self.folder / SCRIPT).read_bytes(), ADAPTER.read_bytes())
        self.assertEqual(set(verify(self.folder)), {MANIFEST, SCRIPT, "games/go/index.html"})

    def test_tampering_or_missing_script_fails_verification(self):
        package(self.folder)
        (self.folder / "games/go/index.html").write_text("changed", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "copy differs"):
            verify(self.folder)
        package(self.folder)
        (self.folder / "index.html").write_text('<script src="index.js"></script>', encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "load once"):
            verify(self.folder)

    def test_unknown_export_leaves_existing_files_untouched(self):
        original = b"not the expected Godot shell"
        (self.folder / "index.html").write_bytes(original)
        with self.assertRaisesRegex(ValueError, "loader anchor"):
            package(self.folder)
        self.assertEqual((self.folder / "index.html").read_bytes(), original)
        self.assertFalse((self.folder / "games").exists())

    def test_pages_prepare_and_assemble_preserve_game_and_bridge(self):
        package(self.folder)
        (self.folder / "index.pck").write_bytes(b"fixture pck")
        (self.folder / "index.js").write_bytes(b"fixture engine")
        (self.folder / "THIRD_PARTY_NOTICES.txt").write_text("fixture", encoding="utf-8")
        spec = importlib.util.spec_from_file_location("pages_package", ROOT / "deploy/github-pages/package.py")
        pages = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(pages)
        packed = Path(self.temp.name) / "packed"
        assembled = Path(self.temp.name) / "site"
        pages.prepare(self.folder, packed)
        paths = {item["path"] for item in json.loads((packed / "manifest.json").read_text(encoding="utf-8"))["files"]}
        self.assertTrue({MANIFEST, SCRIPT, "games/go/index.html"}.issubset(paths))
        pages.assemble(packed, assembled)
        self.assertEqual(set(verify(assembled)), {MANIFEST, SCRIPT, "games/go/index.html"})


if __name__ == "__main__":
    unittest.main()
