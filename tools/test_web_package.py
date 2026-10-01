"""Check release integrity and safe pruning with tiny temporary packages."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("web_package", ROOT / "deploy/github-pages/package.py")
PACKAGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGE)


class WebPackageTests(unittest.TestCase):
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
