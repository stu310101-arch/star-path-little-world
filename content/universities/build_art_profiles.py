"""Apply the manually curated visual brief to all 138 editorial cards.

Run from any directory with Python. The TSV is an authored choice of source
features, not a random seed. Layouts follow the featured landscape or learning
environment; neither school IDs nor hashes influence shape, color or placement.
Document excerpts must exist verbatim; official additions carry distinct URLs
and a review date, never a fabricated quote from the supplied document.
"""
from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import import_university_content as importer

HERE = Path(__file__).resolve().parent
MODULES = {
    "palm_avenue": "成列高幹棕櫚與筆直步道", "tree_grove": "成叢樹冠與林下空地",
    "lake": "低矮水池與環岸", "river": "長形河帶", "coast": "不規則海岸與海面",
    "hill": "隆起山丘", "terrace": "分層平台與階梯", "lawn": "開闊草坪",
    "farm_plots": "分畦田地", "bridge": "跨越型橋梁", "academic_block": "教學與討論量體",
    "historic_hall": "歷史街屋語彙", "chapel": "尖頂禮堂", "library": "閱讀研究書館",
    "gallery": "開放展廊", "stage": "舞臺與階梯觀眾席", "hospital": "醫療照護雙量體",
    "laboratory": "實驗操作櫃與研究量體", "workshop": "開放工坊與製作臺", "hangar": "拱頂航空機棚",
    "track": "橢圓運動跑道", "market": "連續街市店面", "station": "交通月臺與站棚",
    "food_stall": "餐飲工作臺與食品陳列", "robot_cell": "機械手臂工作單元", "digital_hub": "螢幕與數位工作臺",
    "dormitory": "住宿生活量體", "museum": "收藏展示館", "ship": "船體與海事展示",
    "tea_pavilion": "茶席與涼亭", "sculpture": "雕塑展臺", "fashion_studio": "人臺與服飾工作室",
    "thu_chapel": "四片向上收束的曲面教堂", "ntu_bell": "獨立鐘架與鐘體", "dairy_stall": "乳品瓶罐與實習商店陳列",
    "3d_printer": "可辨認龍門、列印平台與成形工件的3D列印設備",
}

# A module's x/z footprint is at most the kit contract. Scalars here are
# deliberate large/small visual roles, never tiny offsets for artificial uniqueness.
# Slots are (x,z,sx,sy,sz,yaw). All rest on the same base unless noted below.
LAYOUTS = {
    "axis": ("long_table", "長軸樹列帶出校園主路，湖景與閱讀館分列兩側。", [
        (-.3,-.35,1.45,.9,.7,0),(1.5,-.25,.8,.8,.85,0),(-1.6,.4,.75,.78,.65,0),(-.25,.4,.65,.7,.65,0),(1.05,.43,.65,.65,.65,0)]),
    "pond": ("arc_cabinet", "水面佔據一側，教研、林蔭與生活物件沿另一側錯落排列，保留清楚湖岸。", [
        (-1.12,-.05,1.55,.9,1.0,0),(.25,-.38,.65,.85,.65,0),(1.4,-.35,.85,.8,.8,0),(.25,.38,.6,.75,.65,0),(1.5,.38,.7,.75,.65,0)]),
    "ridge": ("stepped_case", "地勢量體先形成高低輪廓，教學與生活場景分成上側、前側兩組。", [
        (-1.25,-.10,1.5,.82,.95,0),(.25,-.38,.7,.85,.65,0),(1.45,-.30,.9,.9,.8,0),(.25,.38,.65,.7,.65,0),(1.5,.42,.6,.7,.6,0)]),
    "shore": ("island_case", "海岸留出大片水色與不規則邊緣，山體、船舶和教學量體各自成群。", [
        (-1.25,0,1.5,.8,1.55,0),(.25,-.35,.75,.85,.7,0),(1.4,-.30,.8,.8,.8,0),(.25,.4,.65,.75,.65,0),(1.5,.4,.65,.65,.65,0)]),
    "chapel": ("island_case", "尖頂禮堂作為視覺重心，農地或教學館舍在兩翼，前緣保留低矮景物。", [
        (-.1,-.22,.9,.92,.75,0),(1.3,-.2,.95,.85,.85,0),(-1.45,-.2,.8,.85,.75,0),(-.9,.48,.75,.7,.65,0),(.7,.48,.65,.65,.65,0)]),
    "clinical": ("twin_pedestal", "醫療與技能訓練形成兩個主量體；日常街區或休閒元素壓低置於前景。", [
        (-.6,-.25,1.2,.9,.9,0),(1.18,-.22,.9,.8,.8,0),(-1.45,.42,.72,.65,.65,0),(.2,.42,.7,.7,.65,0),(1.5,.42,.65,.7,.65,0)]),
    "theatre": ("open_stage", "前後錯落的展演與創作場域，以開放舞臺輪廓和側翼作品建立辨識。", [
        (0,-.25,1.25,.85,.9,0),(-1.42,-.15,.8,.9,.85,0),(1.4,-.2,.8,.8,.8,0),(-.8,.43,.6,.75,.6,0),(.8,.46,.8,.7,.55,0)]),
    "maker": ("workbench", "操作設備、工坊和專業製作空間成為主體，前緣配置街區或生活線索。", [
        (-1.3,-.1,1.15,.92,1.0,0),(.05,-.34,.9,.85,.8,0),(1.35,-.26,.85,.8,.8,0),(.1,.43,.85,.7,.6,0),(1.5,.43,.6,.65,.6,0)]),
    "urban": ("corner_cabinet", "集中館舍與街角店面相互咬合，交通或生活線索在兩翼，呈現城市型學習。", [
        (0,-.25,1.2,.92,.85,0),(-1.45,-.05,.9,.8,.9,0),(1.45,-.1,.75,.8,.8,0),(-.7,.45,.7,.65,.6,0),(.75,.45,.7,.7,.6,0)]),
    "heritage": ("arc_cabinet", "歷史量體與文化場景沿弧形觀看動線排列，前景留白讓尖頂和屋簷可辨。", [
        (-.9,-.18,1.05,.9,.8,0),(.6,-.25,.9,.85,.8,0),(1.65,.35,.6,.7,.65,0),(-1.45,.43,.7,.7,.6,0),(.2,.43,.65,.65,.6,0)]),
    "learning": ("long_table", "閱讀、數位和教學據點形成連續的學習鏈，呈現跨場域而非單一主樓。", [
        (0,-.2,1,.92,.9,0),(-1.5,-.2,.8,.85,.8,0),(1.5,-.2,.8,.8,.8,0),(-.8,.43,.7,.65,.6,0),(.8,.43,.7,.65,.6,0)]),
    "sports": ("island_case", "低矮橢圓跑道保留完整輪廓，訓練、展演與校園景物配置在側翼。", [
        (-1.1,-.05,1.65,.8,1.1,0),(.4,-.35,.75,.92,.75,0),(1.6,-.25,.7,.8,.8,0),(.45,.4,.7,.7,.65,0),(1.65,.42,.55,.6,.55,0)]),
    "gallery": ("corner_cabinet", "展廊和作品量體朝不同方向開口，教學、生活與交通作低矮配景。", [
        (-.85,-.16,1.15,.95,.9,0),(.72,-.30,.95,.8,.85,0),(1.65,.43,.6,.7,.6,0),(-1.55,.47,.65,.65,.5,0),(-.1,.47,.7,.65,.55,0)]),
}
PRIMARY_LAYOUT = {
    "palm_avenue":"axis", "lake":"pond", "river":"axis", "tree_grove":"learning", "hill":"ridge", "terrace":"ridge",
    "coast":"shore", "chapel":"chapel", "thu_chapel":"chapel", "hospital":"clinical", "stage":"theatre", "workshop":"maker", "laboratory":"maker",
    "hangar":"maker", "robot_cell":"maker", "historic_hall":"heritage", "digital_hub":"learning", "library":"learning",
    "track":"sports", "gallery":"gallery", "academic_block":"urban", "food_stall":"maker", "farm_plots":"pond",
    "bridge":"urban", "station":"urban", "market":"urban", "ship":"shore", "fashion_studio":"theatre", "lawn":"pond",
    "museum":"heritage", "dormitory":"learning", "tea_pavilion":"heritage", "sculpture":"gallery",
}

# Explicit hero overrides use the same contract while retaining substantial,
# source-related differences. They are not small random shifts of one template.
HERO = {
    "001": ("long_table", "palm_axis", "長椰林主軸與高傅鐘構成雙焦點；醉月湖作低平水景，圖書館和公館街市縮小放在前緣。", [
        (-.65,-.25,2.1,1.05,1.6,0),(1.3,.5,1.0,1.0,.5,0),(-1.4,.48,.65,.65,.6,0),(1.5,-.15,.95,1.1,1.15,0),(-.15,.48,.5,.5,.5,0)]),
    "006": ("stepped_case", "river_terraces", "放大的分層山坡占據半幅展臺，低平河帶與橋梁在右側；學院與藝文量體退為坡河旁的配景。", [
        (-1.17,-.08,1.9,1.12,1.65,0),(1.0,.48,1.6,.8,.7,0),(1.0,.48,.63,.95,.8,90),(.13,-.3,.6,.75,.65,0),(1.35,-.3,1.0,.9,.85,0)]),
    "003": ("arc_cabinet", "lake_farm", "放大中興湖作完整主景，乳品商店作次焦點；林蔭、田間與實驗量體在湖岸側翼形成較小的教研群。", [
        (-1.1,0,1.95,1.0,1.7,0),(1.45,-.4,.65,.75,.6,0),(.35,-.35,.7,.8,.85,0),(1.25,.4,.95,1.0,1.0,0),(.35,.4,.6,.75,.6,0)]),
    "020": ("island_case", "mountain_harbor", "寬海岸與完整山體形成山海大輪廓，船舶作中型焦點；研究與漁港生活縮成低矮配景。", [
        (-1.15,0,2.0,1.0,1.9,0),(.95,-.25,1.65,1.2,1.1,0),(.4,.43,.9,1.0,.8,0),(1.15,.45,.5,.65,.5,0),(1.85,.45,.45,.5,.5,0)]),
    "009": ("island_case", "chapel_pasture", "四片曲面教堂放大成唯一高主景，牧場、樹列、湖景與乳品小棧縮成側翼校園生活群，留出教堂輪廓。", [
        (-1.05,0,1.8,1.12,1.9,0),(.4,-.35,.85,.8,.85,0),(1.6,-.36,.7,.7,.8,0),(.35,.43,.75,1.0,.8,0),(1.5,.43,.85,.8,.8,0)]),
    "025": ("open_stage", "theatre_terrace", "開放劇場放大朝向玩家，舞臺與觀眾席成為主角；美術館、山坡、工坊與校外河岸集中為側翼配景。", [
        (-1.0,0,1.9,1.05,1.7,0),(.40,-.32,.8,.9,1.0,0),(1.6,-.25,.9,.9,.9,0),(.35,.43,.65,.6,.65,0),(1.45,.43,.95,1.0,.75,0)]),
    "007": ("twin_pedestal", "medical_street", "醫院與技能訓練雙體面向十全／吉林生活街角，以公園綠意補出市區日常。", LAYOUTS["clinical"][2]),
    "056": ("twin_pedestal", "medical_city", "醫療雙量體放大為主景，實驗研究作次焦點；吳興街區和象山線索縮成側翼，區分專業與附近生活。", [
        (-1.05,0,1.8,1.05,1.65,0),(1.0,-.25,1.05,.9,1.0,0),(.5,.43,.7,.6,.6,0),(1.65,.4,.6,.7,.85,0)]),
    "075": ("workbench", "urban_laboratory", "可見列印平台、龍門與成形工件的3D列印機放大為主景；實驗和模型製作居側翼，公館街區縮成低矮配景。", [
        (.7,-.25,.9,.8,.9,0),(1.5,.4,.9,.65,.65,0),(-1.05,0,1.9,1.15,1.65,0),(.35,.45,.55,.5,.55,0)]),
    "122": ("workbench", "robot_cell_court", "機械手臂居左，程式控制與機電製作分區，形成可看懂操作鏈的智慧製造場景。", LAYOUTS["maker"][2]),
    "061": ("corner_cabinet", "triangle_gallery", "正文特別指出三角形量體與清水混凝土；展廊斜轉成主角，健康與資訊分居側翼。", [
        (-.9,-.1,1.0,.95,.8,18),(.65,-.3,.85,.85,.7,0),(1.65,.38,.6,.75,.6,0),(-.05,.46,.65,.7,.55,0)]),
}

HERO_FOCUS = {
    "001": ["palm_avenue", "ntu_bell"], "003": ["lake", "dairy_stall"],
    "006": ["terrace"], "009": ["thu_chapel"], "020": ["coast", "hill"],
    "025": ["stage"], "056": ["hospital"], "075": ["3d_printer"],
}

PALETTES = {
    "axis": ("warm_stone","ivory_plaster","palm_green","#8B9B61"),
    "pond": ("moss_green","ivory_plaster","water_teal","#527E78"),
    "ridge": ("layered_stone","warm_plaster","forest_green","#777E5D"),
    "shore": ("coastal_sand","pale_stone","deep_water","#527F94"),
    "chapel": ("pasture_green","warm_plaster","terracotta","#A77650"),
    "clinical": ("pale_stone","ivory_plaster","clinical_teal","#689194"),
    "theatre": ("dark_stone","warm_plaster","stage_burgundy","#966777"),
    "maker": ("concrete","warm_plaster","machine_brass","#AE8954"),
    "urban": ("street_stone","warm_plaster","brick_ochre","#A5785F"),
    "heritage": ("warm_stone","brick_ochre","aged_brass","#A77751"),
    "learning": ("warm_stone","ivory_plaster","book_green","#6B8470"),
    "sports": ("field_green","warm_plaster","track_terracotta","#B27758"),
    "gallery": ("dark_stone","concrete","gallery_burgundy","#8F757D"),
}

NATURE = {"palm_avenue", "tree_grove", "lake", "river", "coast", "hill", "terrace", "lawn", "farm_plots"}
LEARNING = {"academic_block", "library", "gallery", "stage", "hospital", "laboratory", "workshop", "hangar", "robot_cell", "digital_hub", "museum", "ship", "sculpture", "fashion_studio"}


def source_cue(entry: dict, key: str, needle: str, index: int) -> dict:
    if needle.startswith("@"):
        updates = json.loads((HERE / "official_enrichment.json").read_text(encoding="utf-8"))
        cue = updates["entries"][entry["id"]]["module_cues"][needle[1:]].copy()
        cue.update({"id": f"cue-{index + 1}", "source_kind": "official", "reviewed_on": updates["reviewed_on"]})
        return cue
    for section in ["surroundings", "location", "culture", "food", "reviews"]:
        body = entry["sections"][section]
        if needle not in body:
            continue
        # Keep the complete original sentence so restrictions and off-campus
        # context do not vanish while extracting the visually useful phrase.
        quote = next(sentence for sentence in re.split(r"(?<=[。！？])", body) if needle in sentence)
        # A sentence may name campus landmarks, then switch to the outside
        # street. Classify the phrase's own clause, not every feature according
        # to an unrelated occurrence of 校外 later in the same sentence.
        clause = next(part for part in re.split(r"(?=校外)|(?<=；)", quote) if needle in part)
        campus = any(s in clause for s in ["校內", "校園", "本部有", "校本部"])
        nearby = any(s in clause for s in ["校外", "附近", "鄰近", "可往", "課餘可"])
        if section == "food":
            scope = "campus_food" if any(s in quote for s in ["校內", "實習商店", "乳品小棧"]) else "regional_food"
        elif nearby and not campus:
            scope = "nearby_life"
        elif key in LEARNING:
            scope = "learning_symbol"
        elif key in {"market", "station"}:
            scope = "nearby_life"
        elif campus and not nearby:
            scope = "campus_landscape" if key in NATURE else "campus_life"
        else:
            scope = "mixed_context"
        meaning = {
            "campus_landscape": "以校園地景線索安排輪廓，不模擬精確地形",
            "campus_life": "以校園生活空間為線索，不聲稱是特定館舍的實測外觀",
            "nearby_life": "呈現周邊或跨校區生活線索，不把它標成校內建物",
            "learning_symbol": "以通用展品象徵教學、作品或研究，不推定該造型的建築實際存在",
            "campus_food": "呈現正文中的校園食品／實作線索，不保證目前品項供應",
            "regional_food": "呈現地方飲食與產業線索，不聲稱校內有相同農場或店家",
            "mixed_context": "依完整原句呈現校內、周邊或學習情境，未以相鄰擺設推定實際位置",
        }[scope]
        return {"id": f"cue-{index + 1}", "section": section, "feature": needle,
                "quote": quote, "context_scope": scope,
                "interpretation": f"用{MODULES[key]}轉譯「{needle}」；{meaning}。"}
    raise ValueError(f"No exact source cue for {entry['id']}: {key}:{needle}")


def build_profiles() -> dict:
    _, entries = importer.parse_source(importer.SOURCE.read_text(encoding="utf-8-sig"))
    by_id = {entry["id"]: entry for entry in entries}
    profiles = {}
    for line in (HERE / "art-profile-plan.tsv").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        id, intent, specifications = line.split("|")
        specs = [tuple(value.split(":", 1)) for value in specifications.split(";")]
        if id in profiles or not 3 <= len(specs) <= 6:
            raise ValueError(f"Invalid visual brief: {id}")
        if any(key not in MODULES for key, _ in specs):
            raise ValueError(f"Unknown module at {id}")
        layout = PRIMARY_LAYOUT[specs[0][0]]
        display, description, slots = LAYOUTS[layout]
        if id in HERO:
            display, _, description, slots = HERO[id]
        cues = [source_cue(by_id[id], key, needle, i) for i, (key, needle) in enumerate(specs)]
        modules = []
        for i, ((key, needle), slot) in enumerate(zip(specs, slots)):
            x, z, sx, sy, sz, yaw = slot
            modules.append({"key": "component_" + key, "label": cues[i]["feature"],
                            "position": [x, .05 if id == "006" and key == "bridge" else 0, z],
                            "scale": [sx, sy, sz], "rotation_y": yaw,
                            "cue_ids": [cues[i]["id"]]})
        ground, architecture, detail, accent = PALETTES[layout]
        profiles[id] = {"version": 1, "display_variant": display,
                        "composition": {"id": intent, "layout": layout, "description": description},
                        "palette": {"display": "walnut_brass", "ground": ground, "architecture": architecture,
                                    "detail": detail, "accent": accent,
                                    "note": "採共用組件的木、石、抹灰、金屬與景觀材質；色系是藝術指引，不宣稱校舍原色或學校官方色。"},
                        "modules": modules, "source_cues": cues,
                        "representation_note": "依正文線索將校內景觀、周邊生活圈與學習特色作藝術化組合；模組不是精確建築重建，位置與比例不代表實際校圖。"}
        if id in HERO_FOCUS:
            profiles[id]["composition"]["primary_modules"] = ["component_" + key for key in HERO_FOCUS[id]]
            profiles[id]["composition"]["hierarchy_note"] = "主景以大輪廓或較高地標吸引視線，附近生活元素縮小為配景；尺度為藝術化敘事而非測繪。"
    if set(profiles) != set(by_id):
        raise ValueError("Visual briefs must cover every fixed entry ID")
    return profiles


def main() -> None:
    cards = json.loads(importer.EDITORIAL.read_text(encoding="utf-8"))
    profiles = build_profiles()
    for id, profile in profiles.items():
        cards[id]["art_profile"] = profile
    enrichment = HERE / "official_enrichment.json"
    if enrichment.exists():
        updates = json.loads(enrichment.read_text(encoding="utf-8"))
        for id, update in updates["entries"].items():
            cards[id]["summary"] = update["summary"]
            cards[id]["highlights"] = update["highlights"]
            cards[id]["research_update"] = {
                "reviewed_on": updates["reviewed_on"], "sources": update["sources"],
                "note": updates["note"],
            }
            cards[id]["art_profile"]["external_sources"] = update["sources"]
            cards[id]["art_profile"]["reviewed_on"] = updates["reviewed_on"]
            cards[id]["art_profile"]["research_cues"] = update["art_notes"]
            cards[id]["art_profile"]["representation_note"] = "依提供正文與列明的官方補充，將校內景觀、周邊生活圈與學習特色作藝術化組合；模組不是精確建築重建，位置與比例不代表實際校圖。"
    importer.write_json(importer.EDITORIAL, cards)
    print(f"Authored source-grounded art profiles: {len(profiles)}")


if __name__ == "__main__":
    main()
