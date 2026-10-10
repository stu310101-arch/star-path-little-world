"""Check release integrity and safe pruning with tiny temporary packages."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("web_package", ROOT / "deploy/github-pages/package.py")
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class WebPackageTests(unittest.TestCase):
    def test_deferred_pack_survives_assembly_and_hash_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, package, output = (root / name for name in ("source", "package", "output"))
            (source / "packs").mkdir(parents=True)
            (source / "index.html").write_text("new", encoding="utf-8")
            (source / "index.pck").write_bytes(b"boot")
            (source / "index.packs.json").write_text(json.dumps({"version": 1}), encoding="utf-8")
            (source / "index.delivery.json").write_text(json.dumps({"version": 1}), encoding="utf-8")
            (source / "index.delivery.js").write_bytes(b"boot adapter")
            (source / "index.boot.0123456789abcdef.wasm.gz").write_bytes(b"gzip fixture")
            (source / "packs/avatar.pck").write_bytes(b"avatar")
            (source / "packs/avatar.0123456789abcdef.pck.gz").write_bytes(b"compressed avatar")
            (source / "THIRD_PARTY_NOTICES.txt").write_text("notices", encoding="utf-8")
            PACKAGE.prepare(source, package)
            PACKAGE.assemble(package, output)
            self.assertEqual((output / "packs/avatar.pck").read_bytes(), b"avatar")
            self.assertEqual((output / "packs/avatar.0123456789abcdef.pck.gz").read_bytes(), b"compressed avatar")
            self.assertEqual((output / "index.boot.0123456789abcdef.wasm.gz").read_bytes(), b"gzip fixture")
            self.assertEqual((output / "index.delivery.js").read_bytes(), b"boot adapter")
            (package / "files/packs/avatar.pck").write_bytes(b"broken")
            with self.assertRaises(RuntimeError):
                PACKAGE.assemble(package, output)

    def test_stamped_file_omission_and_tampering_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, package, output = (root / name for name in ("source", "package", "output"))
            source.mkdir()
            for name in ("index.html", "index.pck", "THIRD_PARTY_NOTICES.txt", "missing-from-glob.bin"):
                (source / name).write_bytes(b"fixture")
            name = "missing-from-glob.bin"
            stamp = {"files": {name: {"bytes": 7, "sha256": PACKAGE.digest(source / name)}}}
            (source / "index.release.json").write_text(json.dumps(stamp), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "omitted stamped files"):
                PACKAGE.prepare(source, package)
            (source / name).rename(source / "index.extra.bin")
            stamp["files"]["index.extra.bin"] = stamp["files"].pop(name)
            (source / "index.release.json").write_text(json.dumps(stamp), encoding="utf-8")
            PACKAGE.prepare(source, package)
            PACKAGE.assemble(package, output)
            (output / "index.extra.bin").write_bytes(b"changed")
            with self.assertRaisesRegex(RuntimeError, "missing or changed"):
                PACKAGE.verify_release_files(output)

    def test_smaller_release_prunes_only_preceding_manifest_files_and_detects_tampering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, package, output = (root / name for name in ("source", "package", "output"))
            source.mkdir()
            (source / "index.html").write_text("test release", encoding="utf-8")
            (source / "index.pck").write_bytes(b"0123456789")
            (source / "THIRD_PARTY_NOTICES.txt").write_text("notices", encoding="utf-8")
            original_part_size = PACKAGE.PART_SIZE
            PACKAGE.PART_SIZE = 4
            try:
                PACKAGE.prepare(source, package)
                unrelated = package / "parts/keep-user-file.txt"
                unrelated.write_text("preserve", encoding="utf-8")
                self.assertTrue((package / "parts/index.pck.part002").is_file())
                (source / "index.pck").write_bytes(b"new")
                PACKAGE.prepare(source, package)
                self.assertFalse((package / "parts/index.pck.part001").exists())
                self.assertFalse((package / "parts/index.pck.part002").exists())
                self.assertEqual(unrelated.read_text(encoding="utf-8"), "preserve")
                PACKAGE.assemble(package, output)
                self.assertEqual((output / "index.pck").read_bytes(), b"new")
                (package / "parts/index.pck.part000").write_bytes(b"bad")
                with self.assertRaisesRegex(RuntimeError, "Invalid PCK part"):
                    PACKAGE.assemble(package, output)
            finally:
                PACKAGE.PART_SIZE = original_part_size


if __name__ == "__main__":
    unittest.main()
