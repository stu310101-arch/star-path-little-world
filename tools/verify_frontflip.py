"""Run jump integration checks serially on the target laptop; optional start/stop stages."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
GODOT = "C:/Users/xuan9/AppData/Local/Microsoft/WinGet/Links/godot_console.exe"
RUNTIME = Path("C:/Users/xuan9/.cache/codex-runtimes/codex-primary-runtime/dependencies")
NODE = str(RUNTIME / "node/bin/node.exe")
PYTHON = str(RUNTIME / "python/python.exe")
env = os.environ.copy()
env["NODE_PATH"] = str(RUNTIME / "node/node_modules")
env["PYTHONUTF8"] = "1"
env["WORLD_PREVIEW_URL"] = "http://127.0.0.1:8765/index.html?v=20260925-frontflip"

def gd(script, native=False):
    return [GODOT, *([] if native else ["--headless"]), "--path", "game", "--script", "res://" + script]

stages = [
    ("import", [GODOT,"--headless","--path","game","--editor","--import"], 240),
    ("physics", gd("tests/check_jump_physics.gd"), 240),
    ("world-jump", gd("tests/check_jump_world.gd"), 240),
    ("world-regression", gd("tests/world_checks.gd"), 360),
    ("infrastructure-regression", gd("tests/infrastructure_checks.gd"), 480),
    ("camera-regression", gd("tests/camera_drag_checks.gd"), 180),
    ("minimap-regression", gd("tests/minimap_checks.gd"), 180),
    ("static", [PYTHON,"C:/Users/xuan9/.codex/skills/godot/scripts/debug/validate_project.py","game","--godot-bin",GODOT,"--timeout","240","--pretty"], 300),
    ("studio", gd("tools/capture_frontflip_preview.gd", True), 180),
    ("video", [PYTHON,"tools/package_frontflip_preview.py"], 120),
    ("world-capture", gd("tests/check_jump_world.gd", True) + ["--","--capture-jump"], 300),
    ("export", [GODOT,"--headless","--path","game","--export-debug","Web","../build/web/index.html"], 360),
    ("notices", [PYTHON,"tools/package_web_notices.py"], 90),
    ("browser-jump", [NODE,"tools/check_jump_browser.cjs"], 900),
    ("browser-regression", [NODE,"tools/check_world_polish_browser.cjs"], 900),
]
names = [stage[0] for stage in stages]
start = sys.argv[1] if len(sys.argv) > 1 else names[0]
stop = sys.argv[2] if len(sys.argv) > 2 else names[-1]
assert start in names and stop in names and names.index(stop) >= names.index(start)
output = ROOT / "deliverables/jump"
output.mkdir(parents=True, exist_ok=True)
for name, command, timeout in stages[names.index(start):names.index(stop) + 1]:
    print("START", name, flush=True)
    log = output / f"verify-{name}.log"
    with log.open("w", encoding="utf-8") as stream:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
    content = log.read_text(encoding="utf-8")
    if result.returncode or "SCRIPT ERROR:" in content or "\nERROR:" in content:
        print("FAILED", name, "see", log, flush=True)
        raise SystemExit(result.returncode or 1)
    print("PASS", name, flush=True)
print("FRONTFLIP_SELECTED_STAGES_VERIFIED", flush=True)
