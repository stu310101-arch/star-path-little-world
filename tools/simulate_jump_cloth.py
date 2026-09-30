"""Bake standalone Godot jump/drop cloth; no doorway or void scene is created.

Run after opening art/Graduate/Male_Graduate_Jump_Authored.blend:
  blender -b ... --python tools/simulate_jump_cloth.py -- --quality 16

The source must contain the complete 03_JUMP scene. This wrapper retains Walk
and Run and writes the complete result to Male_Graduate_GameReady.blend.
"""
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from simulate_portal_cloth import simulate_portal


def simulate_jump(warmup=25, quality=16, frame_end=None, output=None, warmup_test=False):
    if frame_end is not None and output is None and not warmup_test:
        raise ValueError("A shortened jump probe requires its own --output path")
    return simulate_portal(
        scene_name="03_JUMP",
        warmup=warmup,
        quality=quality,
        frame_end=frame_end,
        output=output or ROOT / "art" / "Graduate" / "Male_Graduate_GameReady.blend",
        warmup_test=warmup_test,
        artifact_prefix="jump",
        action_prefix="Graduate_Jump",
        display_name="Jump",
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--warmup", type=int, default=25)
    parser.add_argument("--quality", type=int, default=16)
    parser.add_argument("--end", type=int)
    parser.add_argument("--output")
    parser.add_argument("--warmup-test", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    simulate_jump(args.warmup, args.quality, args.end, args.output, args.warmup_test)
