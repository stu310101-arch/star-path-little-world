"""Render the existing 03_PORTAL scene from an already prepared .blend.

This script is intended for the caller's Blender background process. It does
not build a scene, save a .blend, change poses, or alter the walk/run scenes.

Blender command suffixes:
    --python tools/render_portal_entry.py -- --probes
    --python tools/render_portal_entry.py --

Probes: frames 1,60,78,86,94,101,110,123 at six samples by default.
Full sequence: frames 1..150 at eight samples. Both use Cycles CPU, four
threads, 800x450, 30 fps. --samples N overrides the default sample count.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
ANIMATION_DIR = ROOT / "art" / "Graduate" / "animation"
PROBE_FRAMES = (1, 60, 78, 86, 94, 101, 110, 123)
FRAME_COUNT = 150
SIZE = (800, 450)


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        header = handle.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"Not a complete PNG header: {path}")
    return struct.unpack(">II", header[16:24])


def write_report(path: Path, report: dict) -> None:
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(path)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--probes", action="store_true")
    parser.add_argument("--samples", type=int, default=None)
    parser.add_argument("--output-dir", type=Path, default=None)
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)
    samples = args.samples if args.samples is not None else (6 if args.probes else 8)
    if samples < 1:
        parser.error("--samples must be a positive integer")

    import bpy

    matches = [scene for scene in bpy.data.scenes if scene.name.startswith("03_PORTAL")]
    if len(matches) != 1:
        raise RuntimeError(f"Expected exactly one scene starting with 03_PORTAL; found {[scene.name for scene in matches]}")
    scene = matches[0]
    if scene.camera is None or scene.camera.type != "CAMERA" or scene.camera.name not in scene.objects:
        raise RuntimeError(f"The prepared scene {scene.name!r} needs an active camera before rendering")
    if bpy.context.window is not None:
        bpy.context.window.scene = scene
    frames = list(PROBE_FRAMES if args.probes else range(1, FRAME_COUNT + 1))
    output_dir = (args.output_dir or ANIMATION_DIR / ("portal_probes" if args.probes else "portal_frames")).expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path = output_dir / "render-validation.json"

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.denoiser = "OPENIMAGEDENOISE"
    scene.cycles.use_adaptive_sampling = False
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.cycles.transmission_bounces = 2
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.resolution_x, scene.render.resolution_y = SIZE
    scene.render.resolution_percentage = 100
    scene.render.pixel_aspect_x = 1.0
    scene.render.pixel_aspect_y = 1.0
    scene.render.fps = 30
    scene.render.fps_base = 1.0
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.image_settings.compression = 15
    scene.render.use_file_extension = True
    scene.render.film_transparent = False
    scene.render.use_border = False
    scene.render.use_crop_to_border = False
    scene.render.use_persistent_data = False
    scene.frame_start = 1
    scene.frame_end = FRAME_COUNT
    scene.frame_step = 1

    report = {
        "status": "in_progress",
        "startedAtUtc": datetime.now(timezone.utc).isoformat(),
        "sourceBlend": bpy.data.filepath,
        "scene": scene.name,
        "mode": "probes" if args.probes else "full",
        "expectedFrames": frames,
        "size": list(SIZE),
        "fps": 30,
        "engine": "CYCLES", "device": "CPU", "threads": 4,
        "samples": samples,
        "denoiser": "OPENIMAGEDENOISE",
        "renderedFrames": [],
    }
    write_report(report_path, report)
    try:
        for index, frame in enumerate(frames, 1):
            started = time.perf_counter()
            scene.frame_set(frame)
            # Updating the selected scene also evaluates keyed cloth shapes and camera cuts.
            for view_layer in scene.view_layers:
                view_layer.update()
            output = output_dir / f"frame_{frame:04d}.png"
            temporary = output_dir / f".frame_{frame:04d}.rendering.png"
            scene.render.filepath = str(temporary)
            bpy.ops.render.render(write_still=True, scene=scene.name)
            actual_size = png_size(temporary)
            if actual_size != SIZE:
                raise ValueError(f"Rendered frame {frame} has size {actual_size}, expected {SIZE}")
            if temporary.stat().st_size <= 24:
                raise ValueError(f"Rendered frame is empty: {temporary}")
            temporary.replace(output)
            report["renderedFrames"].append({
                "frame": frame, "file": output.name,
                "sizeBytes": output.stat().st_size,
                "seconds": round(time.perf_counter() - started, 3),
                "camera": scene.camera.name if scene.camera else None,
            })
            write_report(report_path, report)
            print(f"PORTAL_FRAME_DONE frame={frame} progress={index}/{len(frames)} samples={samples}", flush=True)
        for frame in frames:
            output = output_dir / f"frame_{frame:04d}.png"
            if png_size(output) != SIZE:
                raise ValueError(f"Final output size check failed: {output}")
        report["status"] = "complete"
        report["completedAtUtc"] = datetime.now(timezone.utc).isoformat()
        write_report(report_path, report)
        print(f"PORTAL_RENDER_DONE mode={report['mode']} count={len(frames)} output={output_dir}", flush=True)
    except BaseException as error:
        report["status"] = "failed"
        report["error"] = f"{type(error).__name__}: {error}"
        write_report(report_path, report)
        raise


if __name__ == "__main__":
    main()
