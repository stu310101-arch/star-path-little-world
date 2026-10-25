import copy
from pathlib import Path
import struct
import tempfile
import unittest

from batch_discussion_low import coarsen, accessor_bytes
from share_discussion_textures import encode_glb, read_glb


class LowBatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.path = self.root / "garden_low.glb"
        self.binary = bytearray()
        self.doc = {"asset": {"version": "2.0"}, "nodes": [{"name": "SM_Zone_major_Cell_0_0", "mesh": 0, "translation": [10, 0, 0]}, {"name": "SM_Zone_major_Cell_1_0", "mesh": 0, "translation": [20, 0, 0]}], "scenes": [{"nodes": [0, 1]}], "scene": 0, "materials": [{"name": "palette", "doubleSided": True}], "bufferViews": [], "accessors": []}
        streams = [(struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0), 5126, "VEC3"), (struct.pack("<9f", *([0, 0, 1] * 3)), 5126, "VEC3"), (struct.pack("<6f", 0, 0, 1, 0, 0, 1), 5126, "VEC2"), (struct.pack("<12H", *([0, 32768, 65535, 65535] * 3)), 5123, "VEC4"), (struct.pack("<3H", 0, 1, 2), 5123, "SCALAR")]
        for index, (data, kind, shape) in enumerate(streams):
            self.binary.extend(b"\0" * (-len(self.binary) % 4))
            self.doc["bufferViews"].append({"buffer": 0, "byteOffset": len(self.binary), "byteLength": len(data)})
            self.doc["accessors"].append({"bufferView": index, "componentType": kind, "type": shape, "count": 3})
            self.binary.extend(data)
        self.doc["accessors"][3]["normalized"] = True
        self.doc["meshes"] = [{"primitives": [{"attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2, "COLOR_0": 3}, "indices": 4, "material": 0}]}]
        self.doc["buffers"] = [{"byteLength": len(self.binary)}]

    def tearDown(self):
        self.temp.cleanup()

    def run_batch(self):
        self.path.write_bytes(encode_glb(self.doc, self.binary))
        return coarsen(self.path, backup_dir=self.root / "backup", report_path=self.root / "report.json")

    def test_world_vertices_winding_and_vertex_attributes_are_preserved(self):
        report = self.run_batch()
        result, binary = read_glb(self.path)
        self.assertEqual((report["triangles_after"], report["surfaces_after"]), (2, 1))
        node = result["nodes"][0]
        primitive = result["meshes"][0]["primitives"][0]
        positions = list(struct.iter_unpack("<fff", accessor_bytes(result, binary, primitive["attributes"]["POSITION"])))
        world = [tuple(point[i] + node["translation"][i] for i in range(3)) for point in positions]
        self.assertEqual(world, [(10, 0, 0), (11, 0, 0), (10, 1, 0), (20, 0, 0), (21, 0, 0), (20, 1, 0)])
        index_accessor = result["accessors"][primitive["indices"]]
        fmt = "<I" if index_accessor["componentType"] == 5125 else "<H"
        self.assertEqual([v[0] for v in struct.iter_unpack(fmt, accessor_bytes(result, binary, primitive["indices"]))], [0, 1, 2, 3, 4, 5])
        for semantic, source in [("NORMAL", 1), ("TEXCOORD_0", 2), ("COLOR_0", 3)]:
            self.assertEqual(accessor_bytes(result, binary, primitive["attributes"][semantic]), accessor_bytes(self.doc, self.binary, source) * 2)
        self.assertEqual(result["materials"], self.doc["materials"])
        self.assertEqual(Path(report["backup"]).read_bytes(), encode_glb(self.doc, self.binary))

    def test_different_materials_are_not_combined(self):
        self.doc["materials"].append({"name": "metal"})
        self.doc["meshes"].append(copy.deepcopy(self.doc["meshes"][0]))
        self.doc["meshes"][1]["primitives"][0]["material"] = 1
        self.doc["nodes"][1]["mesh"] = 1
        self.assertEqual(self.run_batch()["surfaces_after"], 2)

    def test_unsupported_rotation_is_rejected_before_writing(self):
        self.doc["nodes"][1]["rotation"] = [0, 0, 0, 1]
        before = encode_glb(self.doc, self.binary)
        with self.assertRaisesRegex(ValueError, "Translation-only"):
            self.run_batch()
        self.assertEqual(self.path.read_bytes(), before)

    def test_repeat_is_byte_identical(self):
        self.run_batch()
        first = self.path.read_bytes()
        report = coarsen(self.path, backup_dir=self.root / "backup", report_path=self.root / "report.json")
        self.assertFalse(report["changed"])
        self.assertEqual(self.path.read_bytes(), first)

    def test_embedded_images_are_rejected_without_rewriting_source(self):
        self.doc["images"] = [{"bufferView": 0, "mimeType": "image/png"}]
        before = encode_glb(self.doc, self.binary)
        with self.assertRaisesRegex(ValueError, "share_discussion_textures"):
            self.run_batch()
        self.assertEqual(self.path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
