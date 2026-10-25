"""Both publishing paths retain optional bytes without adding installation work."""
import json
from pathlib import Path
import tempfile
import unittest

from prepare_web_platform import resource_cache_groups, worker


class OptionalResourceCacheConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.paths = {}
        for prefix in ("", "mobile/"):
            folder = self.root / prefix
            folder.mkdir(exist_ok=True)
            packs = {key: {"url": f"packs/{key}-0123456789abcdef.pck"} for key in ("main", "room", "room_shared")}
            manifest = {"packs": packs, "profiles": {"full": ["main"], "low": ["main"]}, "shared_on_demand": ["room", "room_shared"]}
            delivery = {"packs": {key: {"url": f"packs/{key}.0123456789abcdef.pck.gz"} for key in packs}}
            (folder / "index.packs.json").write_text(json.dumps(manifest))
            (folder / "index.delivery.json").write_text(json.dumps(delivery))
            for key in packs:
                self.paths[prefix + key] = [prefix + packs[key]["url"], prefix + delivery["packs"][key]["url"]]

    def tearDown(self):
        self.temp.cleanup()

    def test_direct_worker_maps_optional_raw_fallback_and_gzip_without_prefetching_either(self):
        files = {name: {"bytes": 10, "sha256": name} for paths in self.paths.values() for name in paths}
        files["index.html"] = {"bytes": 10, "sha256": "page"}
        (self.root / "index.release.json").write_text(json.dumps({"build_id": "fixture", "files": files}))
        worker(self.root)
        script = (self.root / "index.service-worker.js").read_text(encoding="utf-8")
        config = json.loads(script.split("const RELEASE = ", 1)[1].split(";\n", 1)[0])
        self.assertEqual(config["profiles"]["desktop"]["full"], [self.paths["main"][1]])
        self.assertEqual(config["shared_on_demand"]["desktop"], sorted(self.paths["room"] + self.paths["room_shared"]))
        self.assertEqual(config["shared_on_demand"]["mobile"], sorted(self.paths["mobile/room"] + self.paths["mobile/room_shared"]))
        self.assertEqual(config["shell"], ["index.html"])

    def test_cloudflare_mapping_protects_actual_chunks_and_keeps_main_profile_mapping(self):
        virtual = {self.paths["room"][1]: {"parts": [{"url": "chunks/room-a.bin"}, {"url": "chunks/room-b.bin"}]},
                   self.paths["main"][1]: {"parts": [{"url": "chunks/main.bin"}]}}
        config = resource_cache_groups(self.root, virtual)
        self.assertEqual(config["profiles"]["desktop"]["full"], ["chunks/main.bin"])
        optional = config["shared_on_demand"]["desktop"]
        self.assertIn("chunks/room-a.bin", optional)
        self.assertIn("chunks/room-b.bin", optional)
        self.assertNotIn(self.paths["room"][1], optional)
        self.assertIn(self.paths["room"][0], optional)
        self.assertNotIn("chunks/main.bin", optional)


if __name__ == "__main__":
    unittest.main()
