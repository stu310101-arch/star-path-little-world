"""Extract measured counters without substituting estimates for missing values."""
import json
from pathlib import Path
import statistics

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "deliverables/performance"


def read(name):
    return json.loads((EVIDENCE / name).read_text(encoding="utf-8"))


def browser_summary(data):
    stages = {}
    for name in ("overview", "rotate_zoom", "near", "fast_turn", "teleport", "near_transition", "teleport_transition"):
        sample = data.get(name)
        if not sample:
            stages[name] = None
            continue
        snapshots = [item.get("metrics") or item.get("state") or {} for item in sample.get("samples", [])]
        fps = [row["fps"] for row in snapshots if "fps" in row]
        last = sample.get("metrics") or {}
        stages[name] = {
            "raf_ms": sample["raf_ms"],
            "fps_sample_median": statistics.median(fps) if fps else None,
            "fps_sample_range": [min(fps), max(fps)] if fps else None,
            "draw_calls_last": last.get("draw_calls"),
            "process_ms_last": last.get("process_ms"),
            "physics_ms_last": last.get("physics_ms"),
            "render_buffer_bytes_last": last.get("render_buffer_bytes"),
            "nodes_last": last.get("nodes"),
            "streaming_last": last.get("streaming"),
            "obstruction_last": last.get("obstruction"),
            "js_heap": sample.get("heap"),
        }
    return {"build_id": data.get("build_id"), "browser": data.get("browser"), "gpu": data.get("gpu"), "viewport": data["viewport"],
            "started": data["started"], "finished": data.get("finished"), "runs": data["runs"],
            "stages": stages, "errors": data["errors"]}


def native_summary(data):
    names = ["overview", "near"] + [f"repeat_unloaded_{i}" for i in range(3)]
    return {"engine": data["engine"], "headless": data["headless"],
            **{key: data[key] for key in ("load_ms", "instantiate_ms", "ready_ms", "failures")},
            "samples": [row for row in data["samples"] if row["stage"] in names], "checks": data["checks"]}


def startup_summary(name):
    if not (EVIDENCE / name).is_file():
        return None
    data = read(name)
    return {key: data.get(key) for key in ("browser", "gpu", "viewport", "build_id", "started", "finished", "runs", "errors")}


def functional_summary():
    if not (EVIDENCE / "release-functional.json").is_file():
        return None
    data = read("release-functional.json")
    # Include outcomes and compact lifecycle counters, not every UI coordinate.
    return {
        **{key: data.get(key) for key in ("browser", "started", "finished", "checks", "errors", "unmeasured", "method", "passed")},
        "build_id": data.get("expected_release", {}).get("build_id"),
        "repeated_entry": [{"iteration": row["iteration"],
                            **{key: row["unloaded"].get(key) for key in ("nodes", "objects", "resources", "render_buffer_bytes", "static_memory_bytes", "streaming")},
                            "js_heap": row.get("heap")} for row in data.get("repeatedEntry", [])],
        "snapshots": [{"name": row["name"], "nodes": (row.get("metrics") or {}).get("nodes"),
                       "streaming": (row.get("metrics") or {}).get("streaming"),
                       "graphics": (row.get("metrics") or {}).get("graphics"),
                       "obstruction": (row.get("metrics") or {}).get("obstruction"),
                       "js_heap": row.get("heap")} for row in data.get("snapshots", [])],
    }


if __name__ == "__main__":
    output = {
        "notes": [
            "Single local run per build, not a statistical guarantee for other devices.",
            "ready_ms is world_ready signal; excludes later first-render/input latency.",
            "warm means same browser context revisited; PCK/WASM may transfer again (see Resource Timing).",
            "Headless data measures initialization, retained memory and nodes, not GPU rendering/FPS.",
            "Web release static-memory monitor returns zero/unavailable; JS heap is not total browser/WASM/GPU memory.",
            "Process time is a whole-engine monitor, not isolated GDScript profiler time.",
            "Old export exposed debug telemetry; new build is release. Compiler/debug differences are part of the artifact comparison.",
            "Startup-only supplement records first rAF callback after world_ready, not physical GPU presentation or input-response latency.",
        ],
        "browser": {"before": browser_summary(read("before.json")), "after": browser_summary(read("after-final.json"))},
        "native": {"before": native_summary(read("before-native.json")), "after": native_summary(read("after-native.json"))},
        "startup_supplement": {"before": startup_summary("before-startup.json"), "after": startup_summary("after-startup.json")},
        "functional": functional_summary(),
        "release": json.loads((ROOT / "_site/index.release.json").read_text(encoding="utf-8")),
    }
    target = ROOT / "docs/performance-measurements.json"
    target.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(target)
