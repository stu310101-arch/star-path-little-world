import base64
import copy
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from share_discussion_textures import encode_glb, ensure_mipmaps, externalize, read_glb, share_textures

PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")
POSITIONS = struct.pack("<fffffffff", 0, 0, 0, 1, 0, 0, 0, 1, 0)


def source(path):
    document = {"asset": {"version": "2.0"}, "buffers": [{"byteLength": len(POSITIONS) + len(PNG)}],
                "bufferViews": [{"buffer": 0, "byteLength": len(POSITIONS)},
                                {"buffer": 0, "byteOffset": len(POSITIONS), "byteLength": len(PNG)}],
                "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3"}],
                "images": [{"bufferView": 1, "mimeType": "image/png", "name": "Paper"}],
                "textures": [{"source": 0}], "materials": [{"name": "Paper", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
                "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
                "nodes": [{"mesh": 0}], "scenes": [{"nodes": [0]}], "scene": 0}
    path.write_bytes(encode_glb(document, POSITIONS + PNG))
    return copy.deepcopy(document)


class TextureTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_geometry_materials_and_image_bytes_are_exact(self):
        path = self.root / "test.glb"
        before = source(path)
        result = externalize(path)
        after, binary = read_glb(path)
        self.assertEqual(binary, POSITIONS)
        self.assertEqual(after["accessors"], before["accessors"])
        self.assertEqual(after["materials"], before["materials"])
        self.assertEqual(after["nodes"], before["nodes"])
        self.assertEqual((self.root / after["images"][0]["uri"]).read_bytes(), PNG)
        self.assertEqual(result["removed_image_views"], 1)

    def test_two_scenes_share_one_file(self):
        paths = [self.root / name for name in ("garden.glb", "device.glb")]
        for path in paths: source(path)
        report = share_textures(paths)
        self.assertEqual(report["unique_textures_written"], 1)
        self.assertEqual(len(list((self.root / "shared_textures").glob("*.png"))), 1)
        self.assertEqual(read_glb(paths[0])[0]["images"], read_glb(paths[1])[0]["images"])

    def test_repeat_is_idempotent(self):
        path = self.root / "test.glb"
        source(path)
        externalize(path)
        before = path.read_bytes()
        self.assertFalse(externalize(path)["changed"])
        self.assertEqual(path.read_bytes(), before)

    def test_shared_textures_keep_3d_mipmaps(self):
        path = self.root / "test.glb"
        source(path)
        externalize(path)
        document, _ = read_glb(path)
        image = self.root / document["images"][0]["uri"]
        settings = Path(str(image) + ".import")
        self.assertIn("mipmaps/generate=true", settings.read_text())
        settings.write_text('[remap]\nuid="uid://preserved"\n[params]\ncompress/mode=0\nmipmaps/generate=false\n', encoding="utf-8")
        self.assertTrue(ensure_mipmaps(image))
        self.assertIn('uid="uid://preserved"', settings.read_text())
        self.assertIn("mipmaps/generate=true", settings.read_text())
        self.assertFalse(ensure_mipmaps(image))

    def test_existing_hash_file_must_match(self):
        path = self.root / "test.glb"
        source(path)
        folder = self.root / "shared_textures"
        folder.mkdir()
        (folder / f"tex_{hashlib.sha256(PNG).hexdigest()}.png").write_bytes(b"damaged")
        before = path.read_bytes()
        with self.assertRaises(ValueError): externalize(path)
        self.assertEqual(path.read_bytes(), before)

    def test_buffer_references_are_remapped_after_image_removal(self):
        path = self.root / "test.glb"
        document = source(path)
        document["bufferViews"].reverse()
        document["bufferViews"][0]["byteOffset"] = 0
        document["bufferViews"][1]["byteOffset"] = len(PNG) + (-len(PNG) % 4)
        document["images"][0]["bufferView"] = 0
        document["accessors"][0]["bufferView"] = 1
        binary = PNG + b"\0" * (-len(PNG) % 4) + POSITIONS
        document["buffers"][0]["byteLength"] = len(binary)
        path.write_bytes(encode_glb(document, binary))
        externalize(path)
        after, data = read_glb(path)
        self.assertEqual(after["accessors"][0]["bufferView"], 0)
        self.assertEqual(data, POSITIONS)

    def test_real_device_geometry_is_unchanged(self):
        actual = Path(__file__).resolve().parents[1] / "game/assets/discussion_garden/message_device_campus.glb"
        path = self.root / "device.glb"
        document, source_binary = read_glb(actual)
        binary = bytearray(source_binary)
        # The production source is already externalized after a normal build.
        # Embed its same bytes in the temporary fixture to exercise a fresh run.
        for image in document.get("images", []):
            if "uri" not in image: continue
            contents = (actual.parent / image.pop("uri")).read_bytes()
            binary.extend(b"\0" * (-len(binary) % 4))
            image["bufferView"] = len(document["bufferViews"])
            document["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(contents)})
            binary.extend(contents)
        document["buffers"][0]["byteLength"] = len(binary)
        path.write_bytes(encode_glb(document, bytes(binary)))
        result = externalize(path)
        self.assertTrue(result["changed"])
        self.assertGreater(result["geometry_views_preserved"], 0)
        self.assertGreater(len(result["textures"]), 0)


if __name__ == "__main__": unittest.main()
