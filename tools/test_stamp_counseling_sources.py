"""Room art and import settings must affect the release source identity."""
from pathlib import Path
import tempfile
import unittest

from stamp_web_release import counseling_source_paths, source_digest


class CounselingStampTests(unittest.TestCase):
    def test_every_canonical_room_input_changes_the_source_stamp(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            paths = sorted(counseling_source_paths(root))
            self.assertEqual(len(paths), 27)
            self.assertEqual(sum(path.suffix == ".png" for path in paths), 11)
            self.assertEqual(sum(path.suffix == ".import" for path in paths), 12)
            self.assertTrue({f"joinery_{kind}.png{suffix}" for kind in ("base", "normal", "rough")
                             for suffix in ("", ".import")} <= {path.name for path in paths})
            for path in paths:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b"original\n")
            baseline = source_digest(paths, root)
            for path in paths:
                with self.subTest(input=path.name):
                    path.write_bytes(b"changed\n")
                    self.assertNotEqual(source_digest(paths, root), baseline)
                    path.write_bytes(b"original\n")
            extracted = root / "game/assets/counseling_room/counseling_room_duplicate.png"
            extracted.write_bytes(b"unwanted imported extraction")
            self.assertNotIn(extracted, counseling_source_paths(root))
            self.assertEqual(source_digest(paths, root), baseline)

    def test_text_normalization_stays_stable_but_binary_changes_do_not(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            text = root / "map.png.import"
            binary = root / "map.png"
            text.write_bytes(b"settings\nvalue\n")
            binary.write_bytes(b"pixels\n")
            baseline = source_digest([text, binary], root)
            text.write_bytes(b"settings\r\nvalue\r\n")
            self.assertEqual(source_digest([text, binary], root), baseline)
            binary.write_bytes(b"pixels\r\n")
            self.assertNotEqual(source_digest([text, binary], root), baseline)


if __name__ == "__main__":
    unittest.main()
