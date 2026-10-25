"""Source patch restoration must include new files without disturbing a real index."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from snapshot_admissions_source import MANIFEST_NAME, PATCH_NAME, restore, snapshot, verify


class AdmissionsSourceSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="starpath-snapshot-test-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "upstream"
        self.source.mkdir()
        self.run_git("init", "--quiet")
        self.run_git("config", "core.autocrlf", "true")
        self.write(".gitignore", b"node_modules/\nout/\n.env*\n*.pem\n")
        self.write("page.ts", b"original source\n")
        self.write("remove.ts", b"to delete\n")
        self.write("picture.bin", bytes(range(256)))
        self.run_git("add", ".")
        self.run_git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Pinned upstream")
        self.base = self.run_git("rev-parse", "HEAD").decode().strip()
        self.output = self.root / "snapshot"

    def tearDown(self):
        self.temporary.cleanup()

    def run_git(self, *args):
        return subprocess.check_output(["git", *args], cwd=self.source, stderr=subprocess.DEVNULL)

    def write(self, name, payload):
        path = self.source / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)

    def change_source(self):
        self.write("page.ts", b"staged edit\r\n")
        self.run_git("add", "page.ts")
        self.write("page.ts", b"actual working edit\r\n")
        self.write("new feature.ts", "新增來源\n".encode())
        self.write("new.bin", b"\0new binary\xff\n")
        self.write("picture.bin", bytes(reversed(range(256))))
        (self.source / "remove.ts").unlink()
        self.write("node_modules/ignored.js", b"not source")
        self.write("out/index.html", b"not source")
        self.write(".env.local", b"secret must be excluded")
        self.write("private.pem", b"private key must be excluded")

    def test_restores_modified_untracked_binary_deleted_sources_and_preserves_index(self):
        self.change_source()
        status = self.run_git("status", "--porcelain=v1", "-z")
        index = (self.source / ".git/index").read_bytes()
        manifest = snapshot(self.source, self.output, str(self.source))
        self.assertEqual((self.source / ".git/index").read_bytes(), index)
        self.assertEqual(self.run_git("status", "--porcelain=v1", "-z"), status)
        self.assertEqual(manifest["source_base_commit"], self.base)
        self.assertIn("new feature.ts", manifest["source_files"])
        self.assertNotIn("remove.ts", manifest["source_files"])
        self.assertNotIn(".env.local", manifest["source_files"])
        self.assertNotIn("node_modules/ignored.js", manifest["source_files"])
        self.assertIn(b"GIT binary patch", (self.output / PATCH_NAME).read_bytes())
        verify(self.source, self.output, original_bytes=True)
        restored = self.root / "restored"
        self.assertTrue(restore(self.output, restored)["verified"])
        self.assertEqual((restored / "page.ts").read_bytes(), b"actual working edit\n")
        self.assertEqual((restored / "new feature.ts").read_bytes(), "新增來源\n".encode())
        self.assertEqual((restored / "new.bin").read_bytes(), b"\0new binary\xff\n")
        self.assertFalse((restored / "remove.ts").exists())
        self.assertFalse((restored / ".env.local").exists())
        restored_status = subprocess.check_output(["git", "status", "--porcelain=v1"], cwd=restored).decode()
        self.assertIn("?? new.bin", restored_status)
        self.assertIn(" M page.ts", restored_status)

    def test_deterministic_snapshot_and_tampering_detection(self):
        self.change_source()
        snapshot(self.source, self.output, str(self.source))
        first = {name: (self.output / name).read_bytes() for name in (PATCH_NAME, MANIFEST_NAME)}
        snapshot(self.source, self.output, str(self.source))
        self.assertEqual(first, {name: (self.output / name).read_bytes() for name in first})
        self.write("new feature.ts", b"tampered source")
        with self.assertRaisesRegex(ValueError, "inventory differs"):
            verify(self.source, self.output)
        (self.output / PATCH_NAME).write_bytes(first[PATCH_NAME] + b"tamper")
        with self.assertRaisesRegex(ValueError, "patch hash mismatch"):
            restore(self.output, self.root / "not-created")
        self.assertFalse((self.root / "not-created").exists())

    def test_existing_destination_and_tracked_secrets_are_refused(self):
        snapshot(self.source, self.output, str(self.source))
        with self.assertRaisesRegex(ValueError, "must be absent"):
            restore(self.output, self.source)
        self.write(".env.local", b"tracked secret")
        self.run_git("add", "--force", ".env.local")
        with self.assertRaisesRegex(ValueError, "Secret/configuration"):
            snapshot(self.source, self.output, str(self.source))


if __name__ == "__main__":
    unittest.main()
