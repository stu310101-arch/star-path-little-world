import tempfile
import unittest
from pathlib import Path

from package_account_bridge import SCRIPT, MANIFEST, package, verify


class AccountPackageTests(unittest.TestCase):
    def test_both_variant_packages_are_idempotent_and_verified(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for folder in [root, root / "mobile"]:
                folder.mkdir(exist_ok=True)
                (folder / "index.html").write_text('<html><script src="index.js"></script></html>', encoding="utf-8")
                package(folder)
                first = (folder / "index.html").read_bytes()
                package(folder)
                self.assertEqual((folder / "index.html").read_bytes(), first)
                self.assertEqual(verify(folder), [MANIFEST, SCRIPT])
                self.assertIn(b'/admissions/host/', (folder / SCRIPT).read_bytes())

    def test_unknown_loader_does_not_modify_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "index.html").write_text("unexpected", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "loader anchor"):
                package(folder)
            self.assertEqual((folder / "index.html").read_text(), "unexpected")
            self.assertFalse((folder / SCRIPT).exists())

    def test_tampered_bridge_fails_verification(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            (folder / "index.html").write_text('<script src="index.js"></script>', encoding="utf-8")
            package(folder)
            (folder / SCRIPT).write_text("changed", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "copy differs"):
                verify(folder)


if __name__ == "__main__":
    unittest.main()
