"""Verify delivery boundaries with tiny synthetic files; never use user accounts."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import package_recommendation_delivery as delivery
from snapshot_admissions_source import canonical_json


class RecommendationDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.windows, self.web, self.output = (self.root / name for name in ("windows", "cloudflare", "delivery"))
        self.write("game/scripts/recommendation_room.gd", b"extends Node3D\n")
        self.write("asset.blend", b"editable source")
        for name in delivery.ACCOUNT_FILES:
            self.write("admissions-site/" + name, b"{}")
        source_files = {"lib/recommendationService.ts": "a" * 64}
        snapshot = {"version": 1, "source_base_commit": "a" * 40,
                    "source_repository": "https://github.com/example/admissions", "patch_file": "integration.patch",
                    "patch_sha256": hashlib.sha256(b"synthetic patch").hexdigest(), "source_files": source_files,
                    "source_sha256": hashlib.sha256(canonical_json(source_files)).hexdigest(),
                    "source_modes": {name: "100644" for name in source_files}, "working_tree_files": source_files,
                    "working_tree_sha256": hashlib.sha256(canonical_json(source_files)).hexdigest()}
        self.write_json("integrations/admissions/source-manifest.json", snapshot)
        self.write("integrations/admissions/integration.patch", b"synthetic patch")
        for name in ("LittleWorld.exe", "LittleWorld.pck", "index.packs.json"):
            self.write("windows/" + name, b"{}")
        self.native_manifest = {"native_files": {name: delivery.sha_file(self.windows / name) for name in ("LittleWorld.exe", "LittleWorld.pck", "index.packs.json")},
                                "debug_candidate": False,
                                "recommendation_source_sha256": {"scripts/recommendation_room.gd": delivery.sha_file(self.root / "game/scripts/recommendation_room.gd")}}
        self.write_json("windows/release.json", self.native_manifest)
        self.write_json("cloudflare/site/admissions/firebase-config.json", {"apiKey": "public-sdk-key", "projectId": "demo"})
        self.write_json("cloudflare/site/admissions-source.json", {"source_base_commit": snapshot["source_base_commit"], "source_files": source_files})
        self.write("cloudflare/site/index.html", b"synthetic candidate")
        self.write("cloudflare/auth-worker.js", b"export default {}")
        self.write_json("cloudflare/wrangler.jsonc", {})
        files = {path.relative_to(self.web / "site").as_posix(): {"sha256": delivery.sha_file(path), "bytes": path.stat().st_size}
                 for path in (self.web / "site").rglob("*") if path.is_file()}
        self.web_manifest = {"build_id": "synthetic-build", "files": files}
        self.write_json("cloudflare/site/index.release.json", self.web_manifest)
        self.write_json("cloudflare/verification.json", {"passed": True, "build_id": "synthetic-build", "auth_worker_sha256": delivery.sha_file(self.web / "auth-worker.js")})
        self.addCleanup(patch.stopall)
        patch.object(delivery, "ROOT", self.root).start()
        patch.object(delivery, "asset_inventory", lambda: {"asset.blend": self.root / "asset.blend"}).start()

    def write(self, name: str, data: bytes):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def write_json(self, name: str, data):
        self.write(name, json.dumps(data).encode())

    def plan(self):
        return delivery.plan(self.windows, self.web, self.output, "20261025")

    def test_dry_run_validates_without_creating_output(self):
        result = delivery.describe(self.plan())
        self.assertFalse(result["writes_performed"])
        self.assertTrue(result["release_hashes_verified"])
        self.assertEqual(len(result["archives"]), 3)
        self.assertFalse(self.output.exists())

    def test_zip_content_crc_and_archive_hash_are_verified(self):
        result = delivery.package(self.plan())
        for record in [*result["packages"], result["assets"]]:
            self.assertEqual(delivery.sha_file(self.output / record["file"]), record["sha256"])
            self.assertTrue(record["crc_verified"] and record["content_sha256_verified"])
            with zipfile.ZipFile(self.output / record["file"]) as zipped:
                self.assertIsNone(zipped.testzip())
        self.assertTrue((self.output / "source-inventory.json").is_file())
        with self.assertRaisesRegex(ValueError, "must be new"):
            self.plan()

    def test_modified_candidate_bytes_cannot_match_release_inventory(self):
        self.write("windows/LittleWorld.pck", b"changed")
        with self.assertRaisesRegex(ValueError, "Release hash mismatch"):
            self.plan()

    def test_changed_source_or_snapshot_is_rejected(self):
        self.write("game/scripts/recommendation_room.gd", b"changed")
        with self.assertRaisesRegex(ValueError, "Release hash mismatch"):
            self.plan()
        self.write("game/scripts/recommendation_room.gd", b"extends Node3D\n")
        self.write("integrations/admissions/integration.patch", b"changed")
        with self.assertRaisesRegex(ValueError, "Snapshot patch hash mismatch"):
            self.plan()

    def test_worker_and_web_payload_hashes_are_checked(self):
        self.write("cloudflare/site/index.html", b"changed")
        with self.assertRaisesRegex(ValueError, "Release hash mismatch"):
            self.plan()
        self.write("cloudflare/site/index.html", b"synthetic candidate")
        self.write("cloudflare/auth-worker.js", b"changed")
        with self.assertRaisesRegex(ValueError, "matching successful verification"):
            self.plan()

    def test_unlisted_or_private_session_files_are_rejected(self):
        self.write("windows/qa-session.json", b"{}")
        with self.assertRaisesRegex(ValueError, "rejected"):
            self.plan()
        (self.windows / "qa-session.json").unlink()
        self.write_json("windows/extras.json", {"password": "synthetic-test-value"})
        with self.assertRaisesRegex(ValueError, "Credential field"):
            self.plan()

    def test_unsafe_manifest_paths_and_nested_output_are_rejected(self):
        for name in ("../outside", "/absolute", "dir\\file", "C:/outside", "dir//file"):
            with self.assertRaisesRegex(ValueError, "Unsafe"):
                delivery.safe_name(name)
        with self.assertRaisesRegex(ValueError, "must be separate"):
            delivery.plan(self.windows, self.web, self.windows / "delivery", "20261025")

    def test_input_changed_after_plan_cannot_pass_zip_verification(self):
        selected = self.plan()
        self.write("asset.blend", b"changed after validation")
        with self.assertRaisesRegex(ValueError, "differs from verified input"):
            delivery.package(selected)

    def test_local_debug_candidate_requires_named_launcher(self):
        self.native_manifest["debug_candidate"] = True
        self.write_json("windows/release.json", self.native_manifest)
        with self.assertRaisesRegex(ValueError, "explicit launcher"):
            self.plan()
        self.write("windows/Start-Local-Candidate.ps1", b"# local emulator only")
        self.native_manifest["native_files"]["Start-Local-Candidate.ps1"] = delivery.sha_file(self.windows / "Start-Local-Candidate.ps1")
        self.write_json("windows/release.json", self.native_manifest)
        self.assertTrue(self.plan()["provenance"]["windows_debug_candidate"])


if __name__ == "__main__":
    unittest.main()
