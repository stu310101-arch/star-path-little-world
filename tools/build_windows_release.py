"""Export and verify Windows, the account host, embedded Go files and WRY DLL."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from package_web_notices import SOURCES, read_engine_notices
from split_web_packs import exported_entries, read_pack

ROOT = Path(__file__).resolve().parents[1]
WRY_SHA256 = "a8fb72d3570708874f92e5e55384c35127c056c1554eb7a06b5997d050831e5b"
ACCOUNT_SCRIPTS = ("account_session", "account_native_host", "account_terminal_frame",
                   "account_room_bridge", "admissions_room", "admissions_camera_rig",
                   "admissions_furniture_interaction")
ADMISSIONS_MODEL = "assets/admissions_room/admissions_studio.glb"
ADMISSIONS_LAYOUT = "assets/admissions_room/layout.json"
COUNSELING_MODEL = "assets/counseling_room/counseling_room.glb"
COUNSELING_LAYOUT = "assets/counseling_room/layout.json"
INTEREST_CATALOG = "data/interest_catalog.json"
COUNSELING_SCRIPTS = ("counseling_room", "interest_panel", "interest_model", "interest_controller", "interest_protocol", "interest_diagnostics")
RECOMMENDATION_SCRIPTS = ("recommendation_room", "recommendation_panel", "recommendation_controller", "recommendation_protocol", "recommendation_orrery", "recommendation_diagnostics")
GARDEN_SCRIPTS = ("discussion_garden", "discussion_device", "discussion_hud",
                  "discussion_atmosphere", "discussion_render_optimizer", "discussion_avatar_prewarm", "discussion_navigation", "discussion_architecture")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify_garden_export(entries: dict, game: Path) -> dict:
    """Both detail choices must be runnable, and match this exact imported art."""
    models = ["garden.glb", "garden_low.glb"]
    layout = json.loads((game / "assets/discussion_garden/layout.json").read_text(encoding="utf-8"))
    models.extend(zone["device_model"].removeprefix("res://assets/discussion_garden/") for zone in layout["zones"])
    hashes = {}
    for filename in models:
        source = "assets/discussion_garden/" + filename
        exported_entries("res://" + source, entries)
        remap = bytes(entries[source + ".import"]).decode("utf-8")
        target = re.search(r'^path="res://([^"\r\n]+)"', remap, re.M)
        if target is None:
            raise RuntimeError(f"Missing garden import mapping: {filename}")
        local = game / target[1]
        cache = local.with_suffix(".md5").read_text(encoding="utf-8")
        if f'source_md5="{hashlib.md5((game / source).read_bytes()).hexdigest()}"' not in cache:
            raise RuntimeError(f"Stale garden import: {filename}")
        if bytes(entries[target[1]]) != local.read_bytes():
            raise RuntimeError(f"Stale garden export: {filename}")
        hashes[source] = sha(game / source)
    for script in GARDEN_SCRIPTS:
        found = exported_entries(f"res://scripts/{script}.gd", entries)
        if not any(not name.endswith((".import", ".remap", ".uid")) for name in found):
            raise RuntimeError(f"Only metadata was exported for garden script: {script}")
        hashes[f"scripts/{script}.gd"] = sha(game / "scripts" / (script + ".gd"))
    shader = "shaders/discussion_water.gdshader"
    exported_entries("res://" + shader, entries)
    hashes[shader] = sha(game / shader)
    for name in entries:
        if re.search(r"(?:assets/discussion_garden/|\.godot/imported/)(?:garden_|message_device_)[^/]+\.png(?:$|[.-])", name):
            raise RuntimeError(f"Duplicate extracted garden texture was exported: {name}")
    return {"garden_source_sha256": hashes, "garden_layout_sha256": sha(game / "assets/discussion_garden/layout.json")}


def verify_admissions_export(entries: dict, game: Path) -> dict:
    """Check runnable resources, exact layout, and current imported model bytes."""
    required = ["scenes/admissions_room.tscn", ADMISSIONS_MODEL,
                *(f"scripts/{name}.gd" for name in ACCOUNT_SCRIPTS)]
    exported = {ADMISSIONS_LAYOUT}
    for source in required:
        found = exported_entries("res://" + source, entries)
        if not any(not name.endswith((".import", ".remap", ".uid")) for name in found):
            raise RuntimeError(f"Only metadata was exported for admissions resource: {source}")
        exported.update(found)
    if bytes(entries.get(ADMISSIONS_LAYOUT, b"")) != (game / ADMISSIONS_LAYOUT).read_bytes():
        raise RuntimeError("Exported admissions layout differs from source")
    # Godot removes editor import parameters from exported .import metadata.
    # Compare the compiled scene payload instead, after checking that the
    # local import cache was produced from this exact current Blender GLB.
    remap = bytes(entries.get(ADMISSIONS_MODEL + ".import", b"" )).decode("utf-8")
    target = re.search(r'^path="res://([^"\r\n]+)"', remap, re.M)
    if target is None or not target[1].startswith(".godot/imported/") or not target[1].endswith(".scn"):
        raise RuntimeError("Admissions model is missing its imported scene mapping")
    local = game / target[1]
    cache = local.with_suffix(".md5")
    source_md5 = re.search(r'^source_md5="([a-f0-9]{32})"', cache.read_text(encoding="utf-8"), re.M) if cache.is_file() else None
    if source_md5 is None or source_md5[1] != hashlib.md5((game / ADMISSIONS_MODEL).read_bytes()).hexdigest():
        raise RuntimeError("Admissions model import cache is stale; import the current GLB before export")
    if not local.is_file() or bytes(entries[target[1]]) != local.read_bytes():
        raise RuntimeError("Exported admissions model differs from the current imported scene")
    return {
        "account_source_sha256": {name: sha(game / "scripts" / (name + ".gd")) for name in ACCOUNT_SCRIPTS},
        "admissions_source_sha256": {name: sha(game / name) for name in (ADMISSIONS_MODEL, ADMISSIONS_LAYOUT)},
        "admissions_export_sha256": {name: hashlib.sha256(entries[name]).hexdigest() for name in sorted(exported)},
    }


def verify_counseling_export(entries: dict, game: Path) -> dict:
    """Require the same full room and private-form contract in every native build."""
    for name in entries:
        if re.search(r"(?:assets/counseling_room/|\.godot/imported/)counseling_room_[^/]+\.png(?:$|[.-])", name):
            raise RuntimeError(f"Duplicate extracted counseling texture was exported: {name}")
    sources = ["scenes/counseling_room.tscn", COUNSELING_MODEL,
               *(f"scripts/{name}.gd" for name in COUNSELING_SCRIPTS)]
    delivered = set()
    for source in sources:
        found = exported_entries("res://" + source, entries)
        if not any(not name.endswith((".import", ".remap", ".uid")) for name in found):
            raise RuntimeError(f"Only metadata was exported for counseling resource: {source}")
        delivered.update(found)
    for source in (COUNSELING_LAYOUT, INTEREST_CATALOG):
        if bytes(entries.get(source, b"")) != (game / source).read_bytes():
            raise RuntimeError(f"Exported counseling data differs from source: {source}")
        delivered.add(source)
        sources.append(source)
    remap = bytes(entries.get(COUNSELING_MODEL + ".import", b"")).decode("utf-8")
    target = re.search(r'^path="res://([^"\r\n]+)"', remap, re.M)
    if target is None or not target[1].startswith(".godot/imported/"):
        raise RuntimeError("Counseling model is missing its imported scene mapping")
    local = game / target[1]
    cache = local.with_suffix(".md5")
    expected = hashlib.md5((game / COUNSELING_MODEL).read_bytes()).hexdigest()
    if not cache.is_file() or f'source_md5="{expected}"' not in cache.read_text(encoding="utf-8"):
        raise RuntimeError("Counseling model import cache is stale")
    if not local.is_file() or bytes(entries[target[1]]) != local.read_bytes():
        raise RuntimeError("Exported counseling model differs from current import")
    return {
        "counseling_source_sha256": {source: sha(game / source) for source in sources},
        "counseling_export_sha256": {name: hashlib.sha256(entries[name]).hexdigest() for name in sorted(delivered)},
    }


def verify_recommendation_export(entries: dict, game: Path) -> dict:
    """Both room variants must be current; JSON and compiled scripts are required."""
    sources = ["scenes/recommendation_room.tscn", *(f"scripts/{name}.gd" for name in RECOMMENDATION_SCRIPTS)]
    payloads = set()
    for source in sources:
        found = exported_entries("res://" + source, entries)
        if not any(not name.endswith((".import", ".remap", ".uid")) for name in found):
            raise RuntimeError(f"Only metadata was exported for recommendation resource: {source}")
        payloads.update(found)
    for folder in ("assets/recommendation_room", "generated/low/recommendation"):
        layout, model = folder + "/layout.json", folder + "/recommendation_room.glb"
        if bytes(entries.get(layout, b"")) != (game / layout).read_bytes():
            raise RuntimeError(f"Recommendation layout differs from source: {layout}")
        payloads.add(layout)
        payloads.update(exported_entries("res://" + model, entries))
        remap = bytes(entries[model + ".import"]).decode("utf-8")
        target = re.search(r'^path="res://([^"\r\n]+)"', remap, re.M)
        if target is None:
            raise RuntimeError(f"Missing recommendation model import: {model}")
        local = game / target[1]
        cache = local.with_suffix(".md5").read_text(encoding="utf-8")
        if f'source_md5="{hashlib.md5((game / model).read_bytes()).hexdigest()}"' not in cache:
            raise RuntimeError(f"Stale recommendation model import: {model}")
        if bytes(entries[target[1]]) != local.read_bytes():
            raise RuntimeError(f"Stale recommendation model export: {model}")
        sources.extend((layout, model))
    return {"recommendation_source_sha256": {source: sha(game / source) for source in sources},
            "recommendation_export_sha256": {name: hashlib.sha256(entries[name]).hexdigest() for name in sorted(payloads)}}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--package-only", action="store_true", help="Verify/package an already exported Windows Low build")
    parser.add_argument("--preset", default="Windows Low", choices=["Windows Low", "Windows Standard"])
    parser.add_argument("--output", type=Path)
    parser.add_argument("--editor-recovery-mode", action="store_true", help="Use only after normal import has prepared canonical materials")
    parser.add_argument("--debug-candidate", action="store_true", help="Export a candidate that can use the existing localhost-only emulator host override")
    args = parser.parse_args()
    engine = args.godot.resolve()
    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if not version.startswith("4.7.2.stable."):
        raise RuntimeError("Use matching Godot 4.7.2")
    output = args.output.resolve() if args.output else ROOT / ("build/windows-world" if args.preset == "Windows Standard" else "build/windows-low")
    output.mkdir(parents=True, exist_ok=True)
    if not args.package_only:
        run = subprocess.run([str(engine), "--headless", "--path", str(ROOT / "game"), "--editor",
                              "--export-debug" if args.debug_candidate else "--export-release", args.preset, str(output / "LittleWorld.exe")] + (["--recovery-mode"] if args.editor_recovery_mode else []),
                             capture_output=True, text=True, encoding="utf-8", errors="replace")
        log = run.stdout + run.stderr
        (ROOT / "build/native-games-export.log").write_text(log, encoding="utf-8")
        if run.returncode or re.search(r"SCRIPT ERROR|Parse Error|^ERROR:", log, re.M):
            raise RuntimeError("Windows export failed; see build/native-games-export.log")
    pack = read_pack(output / "LittleWorld.pck")
    for name in ("web_games/go/index.html", "web_games/native_go.html", "addons/godot_wry/WRY.gdextension"):
        if bytes(pack.entries.get(name, b"")) != (ROOT / "game" / name).read_bytes():
            raise RuntimeError(f"Exported resource differs from source: {name}")
    for name in ("data/universities.json", "assets/university_hall/layout.json"):
        if bytes(pack.entries.get(name, b"")) != (ROOT / "game" / name).read_bytes():
            raise RuntimeError(f"Exported university content differs from source: {name}")
    exported_entries("res://scenes/university_hall.tscn", pack.entries)
    exported_entries("res://scenes/login_entry.tscn", pack.entries)
    exported_entries("res://scenes/discussion_garden.tscn", pack.entries)
    for source in ("garden.glb", "message_device.glb"):
        exported_entries(f"res://assets/discussion_garden/{source}", pack.entries)
    garden_layout = "assets/discussion_garden/layout.json"
    if bytes(pack.entries.get(garden_layout, b"")) != (ROOT / "game" / garden_layout).read_bytes():
        raise RuntimeError("Exported discussion garden layout differs from source")
    for zone in json.loads((ROOT / "game" / garden_layout).read_text(encoding="utf-8"))["zones"]:
        device = zone.get("device_model", "message_device.glb")
        if not device.startswith("res://"):
            device = f"res://assets/discussion_garden/{device}"
        exported_entries(device, pack.entries)
    admissions_metadata = verify_admissions_export(pack.entries, ROOT / "game")
    counseling_metadata = verify_counseling_export(pack.entries, ROOT / "game")
    recommendation_metadata = verify_recommendation_export(pack.entries, ROOT / "game")
    garden_metadata = verify_garden_export(pack.entries, ROOT / "game")
    for model in ("atrium", "gallery", "exhibit_kit", "feature_book"):
        exported_entries(f"res://assets/university_hall/{model}.glb", pack.entries)
    for name in pack.entries:
        if re.search(r"(?:assets/university_hall/|\.godot/imported/)(?:booth|theme_[^/]+|feature_(?:palm|dairy|tea))\.glb(?:$|[.-])", name):
            raise RuntimeError(f"Unused university model was exported: {name}")
        if re.search(r"(?:assets/university_hall/|\.godot/imported/)(?:atrium_|booth_|gallery_|theme_|feature_|exhibit_kit_)[^/]+\.png(?:$|[.-])", name):
            raise RuntimeError(f"Duplicate extracted university texture was exported: {name}")
    if sha(output / "godot_wry.dll") != WRY_SHA256:
        raise RuntimeError("Missing or changed pinned WRY Windows library")
    licenses = output / "licenses"
    licenses.mkdir(exist_ok=True)
    notices = ["STAR PATH / LITTLE WORLD - WINDOWS THIRD-PARTY NOTICES", ""]
    for family, source, filename, usage, origin in SOURCES:
        shutil.copyfile(ROOT / source, licenses / filename)
        notices.extend([family, usage, origin, "License: licenses/" + filename, ""])
    engine_notices = read_engine_notices(engine)
    (licenses / "Godot-Engine-MIT.txt").write_text(engine_notices["license"], encoding="utf-8")
    (licenses / "Godot-Third-Party-Licenses.json").write_text(json.dumps(engine_notices["third_party_licenses"], indent=2), encoding="utf-8")
    (licenses / "Godot-Copyright-Information.json").write_text(json.dumps(engine_notices["copyright"], indent=2), encoding="utf-8")
    shutil.copyfile(ROOT / "game/addons/godot_wry/LICENSE", licenses / "Godot-WRY-MIT.txt")
    shutil.copyfile(ROOT / "game/addons/godot_wry/SOURCE.md", licenses / "Godot-WRY-Source.md")
    notices.extend(["Godot " + version, "https://godotengine.org/", "licenses/Godot-Engine-MIT.txt", "",
                    "Godot WRY v1.0.2", "https://github.com/doceazedo/godot_wry", "licenses/Godot-WRY-MIT.txt", ""])
    (output / "THIRD_PARTY_NOTICES.txt").write_text("\n".join(notices), encoding="utf-8")
    (output / "操作說明.txt").write_text(
        "星途 · Windows 遊戲版\n\n"
        "雙擊 LittleWorld.exe；請保留同資料夾的 LittleWorld.pck 與 godot_wry.dll。\n"
        "主世界 → 選擇目的地 → 06 練功區 → 入口按 E。\n"
        "01 興趣輔導室：高一區填寫 RIASEC 六項興趣分數；高三區填寫33種知識分數與適配度／Z分數。\n"
        "走近對應年級的量表裝置按 E，在遊戲內編輯；不需填寫施測日期。\n"
        "最適合與適合各提供25列，可新增；儲存草稿、歷次紀錄及推薦依據保存在本人的星途帳號。\n"
        "也可從世界的「遊戲設定」→「我的興趣量表」修改同一份帳號資料。\n"
        "完成紀錄需填滿六項RIASEC與33項知識分數；適配空白列可留白，雲端保存需要網路。\n"
        "大學展覽館：選擇「大學展覽館」→ 入口按 E；依地區逛展、搜尋校名與收藏學校。\n"
        "展位按 E 閱讀五個面向；Esc 關閉閱讀，返回世界回到原位置。\n"
        "校園印象頁可按「近看校園模型」，拖曳轉向、滾輪或按鈕縮放；Esc 返回展廊。\n"
        "圍棋：第一台電腦椅按 E 坐下，按 F／Enter 或點「進入」。\n"
        "圍棋直接在遊戲視窗內遊玩；Esc／返回練功區回座位，再按 E 起身。\n"
        "單字王：走近中央單字王裝置按 E，以預設瀏覽器開啟指定首頁。\n"
        "https://stu310101-arch.github.io/wordking/?page=home\n"
        "單字王目前仍使用外部瀏覽器與原有帳號。\n\n"
        "落點分析站：進入分析室，走近一般大學、特殊招生或 APCS 工作檯按 E。\n"
        "每張工作檯固定招生類別，換類別請關閉畫面後走到另一張工作檯。\n"
        "走近椅子或沙發按 E 坐下，E／Esc 起身；工作檯座位按 F 可直接使用該桌。\n"
        "入口成績台與世界的登入／我的成績按鈕使用同一個星途帳號。\n"
        "校園生活誌：五個主題區可自由探索；走近任一留言裝置按 E，發表該座主留言或閱讀回覆。\n"
        "五區導覽提供步行方向；Esc 先關閉導覽／操作面板，再返回世界。\n"
        "最低與低畫質使用較輕的花園模型；切換植栽細節後重新進入花園套用。\n"
        "登入會開啟系統瀏覽器，完成登入並核對配對碼後，回遊戲儲存及管理成績。\n"
        "關閉操作畫面回到工作檯前；返回世界回到室外原位置。雲端成績需要網路連線。\n"
        "圍棋與落點分析站需要已安裝 Microsoft Edge WebView2 Runtime。\n"
        "安裝來源：https://developer.microsoft.com/microsoft-edge/webview2/\n"
        "圍棋本體由遊戲內附 HTML 離線載入，不需要連上圍棋網站。\n"
        "棋局保存在 Godot 使用者資料夾 computer_games/webview；與外部瀏覽器存檔分開。\n",
        encoding="utf-8-sig")
    files = sorted(path for path in output.rglob("*") if path.is_file() and path.name != "release.json" and path.suffix != ".log")
    manifest = {"engine": version, "go_source_sha256": sha(ROOT / "game/web_games/go/index.html"),
                "native_files": {path.relative_to(output).as_posix(): sha(path) for path in files},
                "file_bytes": {path.relative_to(output).as_posix(): path.stat().st_size for path in files},
                "wordking_url": "https://stu310101-arch.github.io/wordking/?page=home",
                "account_host": "https://star-path-little-world.star-path-little-world.workers.dev/admissions/host/?platform=native",
                **admissions_metadata,
                **counseling_metadata,
                **recommendation_metadata,
                "debug_candidate": args.debug_candidate,
                **garden_metadata,
                "go_host": "Embedded Windows WebView2 via Godot WRY v1.0.2; no external browser handoff"}
    (output / "release.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Windows release verified: " + str(output))


if __name__ == "__main__":
    main()
