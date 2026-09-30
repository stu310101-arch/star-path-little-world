"""Build, check and export aquatic habitats sequentially on the 8 GB workstation."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "deliverables/water-ecology"
GODOT = "C:/Users/xuan9/AppData/Local/Microsoft/WinGet/Links/godot_console.exe"

def run(name, arguments):
    print("START " + name, flush=True)
    with (OUT / (name + ".log")).open("w", encoding="utf-8") as log:
        result = subprocess.run(arguments, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    output = (OUT / (name + ".log")).read_text(encoding="utf-8")
    if result.returncode or "ERROR:" in output or "WARNING:" in output:
        print(output[-8000:], flush=True)
        raise SystemExit(result.returncode or 1)
    print("PASS " + name, flush=True)

def gd(script):
    return [GODOT, "--headless", "--path", "game", "--script", "res://" + script]

run("build", gd("tools/build_water_ecology.gd"))
run("tests", gd("tests/water_ecology_checks.gd"))
if "--visual-only" not in sys.argv:
    run("world", gd("tests/world_checks.gd"))
run("runtime-parse", [GODOT, "--headless", "--debug", "--path", "game", "--check-only", "--script", "res://scripts/lake_life.gd"])
if "--capture" in sys.argv:
    run("native-capture", [GODOT, "--path", "game", "--rendering-method", "gl_compatibility", "--script", "res://tools/capture_waterfronts.gd"])
run("export", [GODOT, "--headless", "--path", "game", "--export-debug", "Web", "../build/web/index.html"])
run("notices", [sys.executable, "-X", "utf8", "tools/package_web_notices.py"])
print("WATER_ECOLOGY_EXPORT_VERIFIED", flush=True)
