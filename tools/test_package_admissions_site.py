"""Verify admissions provenance, secret rejection, and lazy release delivery."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from package_admissions_site import package
from prepare_cloudflare_release import metadata, prepare, verify


class AdmissionsReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        self.exported = self.root / "out"
        self.config = {"apiKey": "public-key", "authDomain": "fixture.firebaseapp.com",
                       "projectId": "fixture", "appId": "public-app-id"}
        for name in ("index.html", "host/index.html", "account/index.html", "account/native/index.html"):
            self.write(self.exported / name, "<html>Fixture</html>")
        self.write(self.exported / "firebase-config.json", self.config)
        self.write(self.source / "page.tsx", "export default function Page() {}")
        for args in (["init", "--quiet"], ["add", "."], ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "commit", "--quiet", "-m", "Fixture"]):
            subprocess.run(["git", *args], cwd=self.source, check=True, capture_output=True)

    def tearDown(self):
        self.temp.cleanup()

    @staticmethod
    def write(path, value):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value) if isinstance(value, dict) else value, encoding="utf-8")

    def world(self):
        folder = self.root / "world"
        for prefix in ("", "mobile/"):
            self.write(folder / prefix / "index.html", '<html><meta name="little-world-build" content="fixture"><script src="index.js"></script></html>')
            self.write(folder / prefix / "index.delivery.js", "fixture")
            self.write(folder / prefix / "index.js", "fixture")
            packs = {key: {"url": f"packs/{key}-0123456789abcdef.pck"} for key in ("main", "counseling_room")}
            for key, item in packs.items():
                self.write(folder / prefix / item["url"], "fixture " + key)
            self.write(folder / prefix / "index.packs.json", {"packs": packs, "profiles": {"full": ["main"], "low": ["main"]}, "shared_on_demand": ["counseling_room"]})
            self.write(folder / prefix / "index.delivery.json", {"packs": {}})
            self.write(folder / prefix / "THIRD_PARTY_NOTICES.txt", "fixture notices")
            self.write(folder / prefix / "licenses/manifest.json", {
                "notice_sha256": metadata(folder / prefix / "THIRD_PARTY_NOTICES.txt")["sha256"], "licenses": []})
        files = {p.relative_to(folder).as_posix(): metadata(p) for p in folder.rglob("*") if p.is_file()}
        self.write(folder / "index.release.json", {"build_id": "fixture", "source_sha256": "fixture", "files": files})
        return folder

    def test_source_revision_and_local_changes_are_recorded(self):
        self.write(self.source / "new.ts", "new feature")
        first = package(self.source, self.exported, self.root / "site-a")
        self.assertIn("new.ts", first["source_files"])
        self.write(self.source / "new.ts", "updated feature")
        second = package(self.source, self.exported, self.root / "site-b")
        self.assertEqual(first["source_base_commit"], second["source_base_commit"])
        self.assertNotEqual(first["source_sha256"], second["source_sha256"])
        self.assertEqual((self.root / "site-b/admissions/host/index.html").read_bytes(), (self.exported / "host/index.html").read_bytes())

    def test_secret_or_emulator_config_is_rejected(self):
        for field in ("private_key", "emulators"):
            self.write(self.exported / "firebase-config.json", {**self.config, field: "must not ship"})
            with self.assertRaisesRegex(ValueError, "Unexpected Firebase"):
                package(self.source, self.exported, self.root / "site")
            self.assertFalse((self.root / "site/admissions").exists())

    def test_missing_host_or_existing_release_is_rejected(self):
        package(self.source, self.exported, self.root / "site")
        with self.assertRaisesRegex(ValueError, "must be absent"):
            package(self.source, self.exported, self.root / "site")
        (self.exported / "host/index.html").unlink()
        with self.assertRaisesRegex(ValueError, "Missing admissions"):
            package(self.source, self.exported, self.root / "new-site")

    def test_release_excludes_admissions_from_world_prefetch_and_detects_tampering(self):
        self.write(self.root / "worker.js", "export default {fetch() {return new Response('fixture')}}")
        self.write(self.root / "vars.json", {"PUBLIC_ORIGIN": "https://fixture.workers.dev", "FIREBASE_PROJECT_ID": "fixture", "FIREBASE_API_KEY": "public-key", "SERVICE_ACCOUNT_EMAIL": "signer@fixture.iam.gserviceaccount.com"})
        report = prepare(self.world(), self.root / "release", admissions_source=self.source,
                         admissions_out=self.exported, auth_worker=self.root / "worker.js", auth_vars=self.root / "vars.json")
        self.assertTrue(report["server_side_code"])
        site = self.root / "release/site"
        worker = (site / "index.service-worker.js").read_text(encoding="utf-8")
        config = json.loads(worker.split("const RELEASE = ", 1)[1].split(";\n", 1)[0])
        self.assertIn("admissions/host/index.html", config["files"])
        self.assertFalse(any(p.startswith("admissions") for p in config["shell"]))
        self.assertEqual(config["shared_on_demand"]["desktop"], ["packs/counseling_room-0123456789abcdef.pck"])
        self.assertNotIn("packs/counseling_room-0123456789abcdef.pck", config["profiles"]["desktop"]["full"])
        deployment = json.loads((self.root / "release/wrangler.jsonc").read_text(encoding="utf-8"))
        self.assertEqual(deployment["assets"]["run_worker_first"], ["/api/native-auth/*"])
        self.assertNotIn("SERVICE_ACCOUNT_PRIVATE_KEY", deployment["vars"])
        self.write(site / "admissions/host/index.html", "tampered")
        with self.assertRaisesRegex(ValueError, "Invalid uploaded file"):
            verify(site)


if __name__ == "__main__":
    unittest.main()
