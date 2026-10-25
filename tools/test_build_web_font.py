"""Authored long-form campus text must be available in the first font subset."""
import json
from pathlib import Path
import tempfile
import unittest

from build_web_font import collect_characters


class WebFontContentTests(unittest.TestCase):
    def test_university_articles_and_ui_are_collected(self):
        with tempfile.TemporaryDirectory() as directory:
            game = Path(directory)
            (game / "data").mkdir()
            (game / "scripts").mkdir()
            article = "國立臺灣大學 椰林大道 臺中 興大 康橋 芎林 澎湖"
            (game / "data/universities.json").write_text(json.dumps({"entries": [{"sections": {"location": article}}]}, ensure_ascii=False), encoding="utf-8")
            ui_labels = "大學館 地區展區 展廊 中庭 收藏手冊"
            (game / "scripts/ui.gd").write_text(f'var label = "{ui_labels}"\n', encoding="utf-8")
            (game / "assets/admissions_room").mkdir(parents=True)
            furniture_labels = "窗邊座椅 諮詢座椅 休息沙發"
            (game / "assets/admissions_room/layout.json").write_text(json.dumps({"title": furniture_labels}, ensure_ascii=False), encoding="utf-8")
            chars = collect_characters(game)
            self.assertTrue(set(map(ord, article + ui_labels + furniture_labels)) <= chars)
            self.assertTrue(set(range(32, 127)) <= chars)


if __name__ == "__main__":
    unittest.main()
