"""Compare recorded, truly rendered garden runs without inferring minimum-hardware FPS."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "deliverables/discussion-overhaul/performance"


def compare(before_name: str, after_name: str) -> dict:
    before = json.loads((FOLDER / before_name).read_text(encoding="utf-8"))
    after = json.loads((FOLDER / after_name).read_text(encoding="utf-8"))
    if before["adapter"] != after["adapter"] or before["frame_limit"] or after["frame_limit"]:
        raise ValueError("Comparisons require the same GPU and uncapped runs")
    if abs(before["scaling_3d"] - after["scaling_3d"]) > .001:
        raise ValueError("Comparisons require the same 3D buffer scale")
    by_point = {row["point"]: row for row in before["samples"]}
    rows = []
    for row in after["samples"]:
        old = by_point[row["point"]]
        rows.append({"point": row["point"],
                     "draw_calls_before": old["draw_calls"]["p50"], "draw_calls_after": row["draw_calls"]["p50"],
                     "primitives_before": old["primitives"]["p50"], "primitives_after": row["primitives"]["p50"],
                     "primitive_change_percent": 100 * (row["primitives"]["p50"] / old["primitives"]["p50"] - 1),
                     "frame_ms_before": old["frame_ms"], "frame_ms_after": row["frame_ms"],
                     "gpu_ms_before": old["gpu_ms"], "gpu_ms_after": row["gpu_ms"],
                     "travelled_distance_after": row.get("travelled_distance", 0)})
    return {"before": before_name, "after": after_name, "rows": rows,
            "load_ready_ms_before": before["load_ready_ms"], "load_ready_ms_after": after["load_ready_ms"],
            "load_max_frame_before": before["loading_frame_ms"]["max"],
            "load_max_frame_after": after["loading_frame_ms"]["max"],
            "static_memory_before": before["static_memory"], "static_memory_after": after["static_memory"],
            "gpu_memory_after": after.get("gpu_memory_bytes"), "loaded_assets_after": after.get("loaded_assets")}


def main() -> None:
    result = {"hardware_limit": "AMD Radeon RX 5700 XT native GL Compatibility. Neither browser/iPhone thermal performance nor minimum-spec hardware was measured. Loading is affected by caches; do not turn these millisecond samples into minimum-device FPS guarantees.",
              "comparison_scope": "Final layout has shorter distances between zones. Views use each layout's logical arrival/control points at the same 65-degree FOV, not identical coordinates or framing. Primitive/draw changes describe the complete revised environment and cannot isolate one optimization. The separate original-art device-batched run is the unchanged-art isolated comparison.",
              "representative_views": compare("baseline.json", "final-minimum.json"),
              "moving": compare("baseline-movement.json", "final-minimum-movement.json")}
    (FOLDER / "comparison.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for label in ("representative_views", "moving"):
        print(label)
        for row in result[label]["rows"]:
            print(f"{row['point']}: draws {row['draw_calls_before']:.0f}->{row['draw_calls_after']:.0f}, "
                  f"primitives {row['primitives_before']:.0f}->{row['primitives_after']:.0f} "
                  f"({row['primitive_change_percent']:+.1f}% change; layout changed); "
                  f"frame p95 {row['frame_ms_before']['p95']:.3f}->{row['frame_ms_after']['p95']:.3f} ms")
        print("load", {k: v for k, v in result[label].items() if k.startswith("load_")})


if __name__ == "__main__":
    main()
