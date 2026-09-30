#!/usr/bin/env python3
"""Package completed graduate animation frames without launching Blender.

Run only after all 36 walk frames and 24 run frames have finished rendering.
The three videos are 9.6 seconds / 288 frames at 30 fps. The side-by-side
preview reserves a 36-pixel title band, so WALK/RUN never cover the source
image. All new artifacts are staged and verified before replacing outputs.

Example (PowerShell, from the repository root)::

    & 'C:\\Users\\xuan9\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\python\\python.exe' tools/package_animation_previews.py
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from fractions import Fraction
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from PIL import Image, ImageDraw, ImageFont, ImageOps


FPS = 30
DURATION_SECONDS = 9.6
OUTPUT_FRAMES = 288
SOURCE_SIZE = (480, 600)
COMPARISON_SIZE = (960, 600)
TITLE_HEIGHT = 36
CLIPS = {"walk": 36, "run": 24}
BACKGROUND = (232, 234, 237)


def run_command(command: list[str]) -> str:
    result = subprocess.run(
        command, capture_output=True, text=True, encoding="utf-8", errors="replace"
    )
    if result.returncode:
        raise RuntimeError(
            f"Command failed ({result.returncode}): {subprocess.list2cmdline(command)}\n"
            f"{result.stdout}\n{result.stderr}"
        )
    return result.stdout


def find_executable(value: str) -> str:
    candidate = Path(value).expanduser()
    if candidate.is_file():
        return str(candidate.resolve())
    discovered = shutil.which(value)
    if discovered:
        return discovered
    raise FileNotFoundError(f"Executable not found: {value}")


def load_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for candidate in ("C:/Windows/Fonts/arialbd.ttf", "C:/Windows/Fonts/arial.ttf"):
        if Path(candidate).is_file():
            return ImageFont.truetype(candidate, size=size)
    return ImageFont.load_default()


def inspect_sources(directory: Path, expected_count: int) -> tuple[list[Path], list[dict]]:
    """At runtime, reject incomplete/mis-sized frames and record provenance."""
    frames = [directory / f"frame_{number:04d}.png" for number in range(1, expected_count + 1)]
    expected_names = {frame.name for frame in frames}
    actual_names = {frame.name for frame in directory.glob("frame_*.png")}
    if actual_names != expected_names:
        missing = sorted(expected_names - actual_names)
        extra = sorted(actual_names - expected_names)
        raise ValueError(f"Incomplete/unexpected frame set in {directory}: missing={missing}, extra={extra}")
    evidence = []
    for frame in frames:
        before = frame.stat()
        with Image.open(frame) as source:
            if source.size != SOURCE_SIZE:
                raise ValueError(f"Expected {SOURCE_SIZE}, got {source.size}: {frame}")
            source.verify()
        digest = hashlib.sha256(frame.read_bytes()).hexdigest()
        after = frame.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise RuntimeError(f"Source frame changed during inspection: {frame}")
        evidence.append(
            {
                "file": frame.name,
                "sizeBytes": after.st_size,
                "mtimeNs": after.st_mtime_ns,
                "sha256": digest,
            }
        )
    return frames, evidence


def encoding_options() -> list[str]:
    return [
        "-an", "-frames:v", str(OUTPUT_FRAMES), "-r", str(FPS),
        "-c:v", "libx264", "-preset", "fast", "-crf", "20",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", "-threads", "2",
    ]


def make_clip(ffmpeg: str, frames_directory: Path, output: Path) -> None:
    run_command(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-filter_threads", "1", "-stream_loop", "-1", "-framerate", str(FPS),
            "-start_number", "1", "-i", str(frames_directory / "frame_%04d.png"),
            "-vf", "setsar=1",
        ]
        + encoding_options()
        + [str(output)]
    )


def make_contact_sheet(frames: list[Path], name: str, output: Path) -> list[int]:
    # Pick eight positions across the cyclic interval, excluding the duplicated endpoint.
    indices = [index * len(frames) // 8 for index in range(8)]
    tile_width, tile_height, caption_height = 300, 402, 27
    sheet = Image.new("RGB", (tile_width * 4, tile_height * 2), BACKGROUND)
    draw = ImageDraw.Draw(sheet)
    font = load_font(14)
    for tile_number, frame_index in enumerate(indices):
        x = (tile_number % 4) * tile_width
        y = (tile_number // 4) * tile_height
        with Image.open(frames[frame_index]) as source:
            tile = ImageOps.contain(
                source.convert("RGB"), (tile_width, tile_height - caption_height), Image.Resampling.LANCZOS
            )
        sheet.paste(
            tile,
            (x + (tile_width - tile.width) // 2, y + caption_height + (tile_height - caption_height - tile.height) // 2),
        )
        draw.text(
            (x + 10, y + 6),
            f"{name.upper()} | Frame {frame_index + 1:02d} | {frame_index / FPS:.2f}s",
            font=font,
            fill=(29, 36, 44),
        )
    sheet.save(output, quality=94, subsampling=0)
    return [index + 1 for index in indices]


def make_title_band(output: Path) -> None:
    band = Image.new("RGB", (COMPARISON_SIZE[0], TITLE_HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(band)
    font = load_font(21)
    for title, center_x in (("WALK", 240), ("RUN", 720)):
        left, top, right, bottom = draw.textbbox((0, 0), title, font=font)
        draw.text(
            (center_x - (right - left) / 2 - left, (TITLE_HEIGHT - (bottom - top)) / 2 - top),
            title,
            font=font,
            fill=(29, 36, 44),
        )
    band.save(output)


def make_comparison(ffmpeg: str, stage: Path) -> None:
    title_band = stage / "title_band.png"
    make_title_band(title_band)
    # Preserve aspect ratio and the whole original image beneath a separate title band.
    column = (
        "scale=480:564:force_original_aspect_ratio=decrease:force_divisible_by=2,"
        "pad=480:600:(ow-iw)/2:36+(564-ih)/2:color=0xE8EAED,setsar=1"
    )
    graph = (
        f"[0:v]{column}[walk];[1:v]{column}[run];"
        "[walk][run]hstack=inputs=2[paired];"
        "[paired][2:v]overlay=x=0:y=0:shortest=1,format=yuv420p[out]"
    )
    run_command(
        [
            ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-filter_complex_threads", "1",
            "-i", str(stage / "walk_preview.mp4"),
            "-i", str(stage / "run_preview.mp4"),
            "-loop", "1", "-framerate", str(FPS), "-i", str(title_band),
            "-filter_complex", graph, "-map", "[out]",
        ]
        + encoding_options()
        + [str(stage / "walk_and_run_preview.mp4")]
    )


def verify_video(ffprobe: str, video: Path, expected_size: tuple[int, int]) -> dict:
    raw = run_command(
        [
            ffprobe, "-v", "error", "-count_frames", "-select_streams", "v:0",
            "-show_entries",
            "stream=codec_name,width,height,pix_fmt,r_frame_rate,avg_frame_rate,duration,nb_frames,nb_read_frames:format=duration,size",
            "-of", "json", str(video),
        ]
    )
    probe = json.loads(raw)
    if len(probe.get("streams", [])) != 1:
        raise ValueError(f"Missing video stream: {video}")
    stream = probe["streams"][0]
    duration = float(probe["format"]["duration"])
    checks = {
        "h264": stream.get("codec_name") == "h264",
        "yuv420p": stream.get("pix_fmt") == "yuv420p",
        "dimensions": (stream.get("width"), stream.get("height")) == expected_size,
        "averageFrameRate": Fraction(stream.get("avg_frame_rate", "0/1")) == FPS,
        "declaredFrameRate": Fraction(stream.get("r_frame_rate", "0/1")) == FPS,
        "declaredFrames": int(stream.get("nb_frames", -1)) == OUTPUT_FRAMES,
        "decodedFrames": int(stream.get("nb_read_frames", -1)) == OUTPUT_FRAMES,
        "duration": abs(duration - DURATION_SECONDS) < 0.001,
    }
    if not all(checks.values()):
        raise ValueError(f"Video validation failed for {video.name}: {checks}; probe={probe}")
    return {"file": video.name, "checks": checks, "ffprobe": probe}


def verify_sources_unchanged(sources: dict) -> None:
    for clip in sources.values():
        for frame, evidence in zip(clip["frames"], clip["evidence"]):
            current = frame.stat()
            if current.st_size != evidence["sizeBytes"] or current.st_mtime_ns != evidence["mtimeNs"]:
                raise RuntimeError(f"Source frame changed while packaging; outputs not replaced: {frame}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--animation-dir", type=Path,
        default=Path(__file__).resolve().parents[1] / "art" / "Graduate" / "animation",
    )
    parser.add_argument("--ffmpeg", default="C:/ffmpeg/bin/ffmpeg.exe")
    parser.add_argument("--ffprobe", default="C:/ffmpeg/bin/ffprobe.exe")
    args = parser.parse_args()
    animation_dir = args.animation_dir.expanduser().resolve()
    if not animation_dir.is_dir():
        raise FileNotFoundError(animation_dir)
    ffmpeg = find_executable(args.ffmpeg)
    ffprobe = find_executable(args.ffprobe)
    sources = {}
    for name, expected_count in CLIPS.items():
        directory = animation_dir / f"{name}_frames"
        frames, evidence = inspect_sources(directory, expected_count)
        sources[name] = {"directory": directory, "frames": frames, "evidence": evidence}
    report = {
        "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
        "fps": FPS,
        "durationSeconds": DURATION_SECONDS,
        "outputFramesPerVideo": OUTPUT_FRAMES,
        "clips": {},
        "videos": [],
        "comparison": {
            "size": list(COMPARISON_SIZE),
            "left": "WALK", "right": "RUN", "titleBandHeight": TITLE_HEIGHT,
            "framing": "Full source images scaled proportionally below a separate title band; no cropping.",
        },
        "visualReview": {
            "status": "not_performed_by_packaging_script",
            "required": "Review newly rendered contact sheets and play all previews, including loop boundaries, for motion and cloth intersections.",
        },
    }
    with tempfile.TemporaryDirectory(prefix=".preview-build-", dir=animation_dir) as stage_name:
        stage = Path(stage_name)
        artifact_names = []
        for name, clip in sources.items():
            print(f"Packaging {name.upper()}: {len(clip['frames'])} source frames...", flush=True)
            video_name = f"{name}_preview.mp4"
            sheet_name = f"{name}_contact_sheet.jpg"
            make_clip(ffmpeg, clip["directory"], stage / video_name)
            sampled_frames = make_contact_sheet(clip["frames"], name, stage / sheet_name)
            report["clips"][name] = {
                "sourceDirectory": clip["directory"].name,
                "sourceFrameCount": len(clip["frames"]),
                "sourceSize": list(SOURCE_SIZE),
                "sourceCycleSeconds": len(clip["frames"]) / FPS,
                "cyclesInPreview": OUTPUT_FRAMES / len(clip["frames"]),
                "contactSheet": sheet_name,
                "contactSheetSourceFrames": sampled_frames,
                "sourceFrames": clip["evidence"],
            }
            report["videos"].append(verify_video(ffprobe, stage / video_name, SOURCE_SIZE))
            artifact_names.extend([video_name, sheet_name])
        print("Packaging WALK / RUN comparison...", flush=True)
        comparison_name = "walk_and_run_preview.mp4"
        make_comparison(ffmpeg, stage)
        report["videos"].append(verify_video(ffprobe, stage / comparison_name, COMPARISON_SIZE))
        artifact_names.append(comparison_name)
        verify_sources_unchanged(sources)
        report["sourceFramesUnchangedDuringPackaging"] = True
        report_path = stage / "preview-validation.json"
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        artifact_names.append(report_path.name)
        for filename in artifact_names:
            (stage / filename).replace(animation_dir / filename)
            print(f"Wrote {filename}", flush=True)
    print("All three previews passed ffprobe decoding, frame-count, format, dimensions, fps, and duration checks.", flush=True)


if __name__ == "__main__":
    main()
