"""Keep shipped release validation separate from editor-hosted exported-PCK QA."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "deliverables/low-end/native"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("release", "editor-pck"), default="release")
    parser.add_argument("--godot", default=shutil.which("godot_console") or shutil.which("godot"))
    parser.add_argument("--driver", help="Explicit diagnostic override; omit for the shipped default driver")
    parser.add_argument("--label", help="Separate evidence folder for diagnostic runs")
    parser.add_argument("--inherit-console", action="store_true", help="Diagnostic retry without CREATE_NO_WINDOW")
    args = parser.parse_args()
    output = OUTPUT / (args.label or args.mode)
    output.mkdir(parents=True, exist_ok=True)
    folder = ROOT / "build/windows-low"
    executable = folder / "LittleWorld.exe"
    pack = folder / "LittleWorld.pck"
    if not executable.is_file() or not pack.is_file():
        raise FileNotFoundError("Export Windows Low before measuring")
    manifest = json.loads((folder / "release.json").read_text(encoding="utf-8"))
    for item in (executable, pack):
        expected = manifest["native_files"][item.name]
        with item.open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if item.stat().st_size != expected["bytes"] or actual != expected["sha256"]:
            raise RuntimeError("Native release artifact changed: " + item.name)
    if args.mode == "release":
        command = [str(executable), "--resolution", "1280x800", "--print-fps", "--", "--capture-tour"]
        method = "Actual release executable/PCK with default driver and shipped capture tour; console one-second FPS only, not P95/input-latency evidence."
    else:
        if not args.godot:
            parser.error("Pass matching --godot editor executable")
        command = [args.godot, "--path", str(folder), "--main-pack", str(pack),
                   "--resolution", "1280x800", "--script", str(ROOT / "game/tests/native_low_end_route.gd"),
                   "--", "--report", str(output / "route.json"), "--captures", str(output)]
        method = "Matching editor hosts unchanged release PCK with external QA script; not the shipped release executable. Default rendering driver."
    if args.driver:
        command[1:1] = ["--rendering-driver", args.driver]
        method += " Explicit diagnostic driver override: " + args.driver
    report = {"method": method, "release": manifest, "command": command, "inherit_console": args.inherit_console,
              "started_epoch_ms": round(time.time()*1000)}
    with (output / "runtime.log").open("w", encoding="utf-8") as log:
        game = subprocess.Popen(command, cwd=folder, stdout=log, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, creationflags=0 if args.inherit_console else subprocess.CREATE_NO_WINDOW)
        sampler = subprocess.Popen([sys.executable, str(ROOT / "tools/observe_process_memory.py"),
                                    "--pid", str(game.pid), "--output", str(output / "memory.json")],
                                   cwd=ROOT, creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            deadline = time.monotonic() + 900
            while game.poll() is None:
                startup_log = (output / "runtime.log").read_text(encoding="utf-8", errors="replace")
                if "Failed to create ANGLE OpenGL window" in startup_log or "compiled without support for path overrides" in startup_log:
                    report["terminated_owned_process_reason"] = "Fatal engine startup error; close only this QA launch instead of leaving an error dialog open."
                    game.terminate()
                    break
                if time.monotonic() >= deadline:
                    report["terminated_owned_process_reason"] = "QA deadline exceeded"
                    game.terminate()
                    break
                time.sleep(.5)
            code = game.wait(timeout=10)
        finally:
            if game.poll() is None:
                game.terminate()  # Only the process launched here, never user apps.
                game.wait(timeout=10)
            sampler.wait(timeout=15)
    report.update(exit_code=code, finished_epoch_ms=round(time.time()*1000))
    text = (output / "runtime.log").read_text(encoding="utf-8", errors="replace")
    report["render_lines"] = [line for line in text.splitlines() if any(k in line for k in ("OpenGL", "ANGLE", "Using Device", "Vulkan"))]
    report["fps_1s"] = [int(value) for value in re.findall(r"(?:Project|Engine) FPS:\s*(\d+)", text)]
    report["errors"] = [line for line in text.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|^ERROR:", line)]
    report["captures"] = []
    if args.mode == "release":
        for name in re.findall(r"^CAPTURE (.+)$", text, re.M):
            original = Path(name.strip())
            if original.is_file():
                target = output / original.name
                shutil.copy2(original, target)
                report["captures"].append(str(target.relative_to(ROOT)))
    elif (output / "route.json").exists():
        route = json.loads((output / "route.json").read_text(encoding="utf-8"))
        report["route_errors"] = route["errors"]
        report["gpu"] = route.get("gpu")
        report["sample_count"] = len(route["samples"])
    else:
        report["errors"].append("QA route did not write report")
    if (output / "memory.json").exists():
        memory = json.loads((output / "memory.json").read_text(encoding="utf-8"))
        rows = memory["samples"]
        report["memory"] = {"method": memory["method"], "samples": len(rows),
                            "peak_private_commit_bytes": max((r["private_bytes_sum"] for r in rows), default=0),
                            "peak_working_set_sum_bytes": max((r["working_set_sum"] for r in rows), default=0),
                            "min_host_available_physical_bytes": min((r["host_available_physical"] for r in rows), default=0)}
    report["world_ready_observed"] = "WORLD_READY" in text
    if not report["world_ready_observed"]:
        report["performance_limit"] = "No game scene was reached: these memory values describe failed engine startup only; gameplay FPS, P95, GPU selection and game memory are unmeasured."
    (output / "summary.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))
    if code or report["errors"] or report.get("route_errors"):
        raise RuntimeError("Native validation failed; inspect " + str(output / "runtime.log"))


if __name__ == "__main__":
    main()
