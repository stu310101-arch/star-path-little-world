"""Sequential fresh Godot QA for the regalia delivery; no rendered window.

Run only after Blender/export jobs have finished. --dry-run launches nothing.
The GLB is read for provenance only; Godot rebuilds its own import cache.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "art/Graduate/Godot"
GODOT = Path.home() / "AppData/Local/Microsoft/WinGet/Links/godot_console.exe"
DEBUG_TOOLS = Path.home() / ".codex/skills/godot/scripts/debug"
EXPECTED_CHECKS = {
    "flash_frame_40", "hide_frame_41", "one_shot_signals", "cancel_then_walk",
    "replay", "world_space_motes", "independent_instances",
    "slow_motion_flash_and_motes", "pause_clock", "default_idle",
    "idle_expected_cycle_duration", "idle_body_and_cloth_loop",
    "idle_breathing_motion", "idle_replay", "cancel_then_idle",
}


def fingerprint(path: Path) -> dict:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    info = path.stat()
    return {"path": str(path), "bytes": info.st_size,
            "mtime_ns": info.st_mtime_ns, "sha256": digest.hexdigest()}


def write_json(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def functional_payload(output: str) -> dict:
    # Consume only this run's stdout, never a possibly stale asset_validation.json.
    for line in reversed(output.splitlines()):
        if line.strip().startswith("{"):
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict) and "event_checks" in payload:
                return payload
    return {}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot-bin", type=Path, default=GODOT)
    parser.add_argument("--timeout", type=float, default=180.0,
                        help="Maximum seconds for each sequential Godot stage.")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    base = [str(args.godot_bin), "--headless", "--debug", "--ignore-error-breaks",
            "--path", str(PROJECT)]
    stages = [
        ("import", base + ["--import"]),
        ("functional", base + ["--script", "res://tests/validate_asset.gd"]),
        ("runtime", base + ["--quit-after", "270", "--fixed-fps", "30"]),
    ]
    if args.dry_run:
        print(json.dumps({"launches_godot": False, "stages": dict(stages)},
                         ensure_ascii=False, indent=2))
        return 0
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    asset = PROJECT / "assets/graduate.glb"
    for required in [args.godot_bin, asset, PROJECT / "project.godot",
                     PROJECT / "tests/validate_asset.gd", DEBUG_TOOLS / "run_project.py"]:
        if not required.is_file():
            parser.error(f"Missing required file: {required}")
    sys.path.insert(0, str(DEBUG_TOOLS))
    from run_project import run  # Reuse Windows child-tree timeout cleanup.
    from godot_log_parser import parse_log

    destination = PROJECT / "tests"
    summary = {"started_utc": datetime.now(timezone.utc).isoformat(),
               "ok": False, "asset": fingerprint(asset), "stages": {}}
    summary_path = destination / "regalia_qa_summary.json"
    write_json(summary_path, summary)
    for name, command in stages:
        print(f"REGALIA_QA_START {name}", flush=True)
        output, exit_code, timed_out, elapsed = run(command, args.timeout)
        log_path = destination / f"regalia_{name}.log"
        log_path.write_text(output, encoding="utf-8")
        diagnostics = parse_log(output, include_warnings=True)
        result = {"ok": exit_code == 0 and not timed_out and diagnostics["counts"]["total"] == 0,
                  "exit_code": exit_code, "timed_out": timed_out,
                  "elapsed_seconds": round(elapsed, 3), "command": command,
                  "log": str(log_path), **diagnostics}
        if name == "functional":
            payload = functional_payload(output)
            result["asset_validation"] = payload
            result["missing_checks"] = sorted(EXPECTED_CHECKS - set(payload.get("event_checks", [])))
            result["ok"] = bool(result["ok"] and payload.get("ok")
                                and not payload.get("failures") and not result["missing_checks"])
            write_json(destination / "regalia_asset_validation.json", payload)
        write_json(destination / f"regalia_{name}_validation.json", result)
        summary["stages"][name] = result
        write_json(summary_path, summary)
        print(f"REGALIA_QA_DONE {name} ok={result['ok']}", flush=True)
        if not result["ok"]:
            break
    summary["asset_after"] = fingerprint(asset)
    summary["asset_unchanged"] = summary["asset_after"] == summary["asset"]
    summary["ok"] = (len(summary["stages"]) == len(stages)
                     and all(item["ok"] for item in summary["stages"].values())
                     and summary["asset_unchanged"])
    summary["finished_utc"] = datetime.now(timezone.utc).isoformat()
    write_json(summary_path, summary)
    print(json.dumps({"ok": summary["ok"], "report": str(summary_path),
                      "asset_sha256": summary["asset"]["sha256"],
                      "stages": {name: item["ok"] for name, item in summary["stages"].items()}},
                     ensure_ascii=False), flush=True)
    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
