"""Package the completed 150-frame portal entry as a 5-second preview.

Run with the bundled Python (Pillow installed) after the full Blender render.
No Blender import, source frame modification, download, or network operation.

Outputs in art/Graduate/animation:
  portal_entry_preview.mp4       H.264/yuv420p, 800x450, 30fps, 150 frames/5s
  portal_entry_contact_sheet.jpg 8 narrative key frames, including the ending
  portal-preview-validation.json source hashes and actual ffprobe decode checks
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


ROOT = Path(__file__).resolve().parents[1]
FRAME_COUNT = 150
FPS = 30
DURATION = 5.0
SIZE = (800, 450)
CONTACT_FRAMES = (1, 60, 78, 86, 94, 101, 110, 150)


def run_command(command: list[str]) -> str:
    result = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {subprocess.list2cmdline(command)}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def executable(value: str) -> str:
    candidate = Path(value).expanduser()
    if candidate.is_file():
        return str(candidate.resolve())
    found = shutil.which(value)
    if found:
        return found
    raise FileNotFoundError(f"Executable not found: {value}")


def inspect_frames(directory: Path) -> tuple[list[Path], list[dict]]:
    frames = [directory / f"frame_{frame:04d}.png" for frame in range(1, FRAME_COUNT + 1)]
    expected = {frame.name for frame in frames}
    actual = {frame.name for frame in directory.glob("frame_*.png")}
    if actual != expected:
        raise ValueError(f"Expected exactly frames 0001..0150 in {directory}; missing={sorted(expected-actual)}, extra={sorted(actual-expected)}")
    evidence = []
    for frame in frames:
        before = frame.stat()
        with Image.open(frame) as image:
            if image.format != "PNG" or image.size != SIZE:
                raise ValueError(f"Expected an {SIZE} PNG: {frame}; got {image.format} {image.size}")
            image.verify()
        digest = hashlib.sha256(frame.read_bytes()).hexdigest()
        after = frame.stat()
        if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
            raise RuntimeError(f"Source frame changed during inspection: {frame}")
        evidence.append({"file": frame.name, "sizeBytes": after.st_size, "mtimeNs": after.st_mtime_ns, "sha256": digest})
    return frames, evidence


def make_contact_sheet(frames: list[Path], output: Path) -> None:
    tile_width, image_height, caption_height = 480, 270, 26
    tile_height = image_height + caption_height
    sheet = Image.new("RGB", (tile_width * 2, tile_height * 4), (19, 24, 32))
    draw = ImageDraw.Draw(sheet)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 14) if font_path.is_file() else ImageFont.load_default()
    for index, frame_number in enumerate(CONTACT_FRAMES):
        x, y = (index % 2) * tile_width, (index // 2) * tile_height
        with Image.open(frames[frame_number - 1]) as source:
            tile = ImageOps.contain(source.convert("RGB"), (tile_width, image_height), Image.Resampling.LANCZOS)
        sheet.paste(tile, (x + (tile_width - tile.width) // 2, y + caption_height + (image_height - tile.height) // 2))
        draw.text((x + 10, y + 5), f"FRAME {frame_number:03d} | {(frame_number-1)/FPS:.2f}s", font=font, fill=(228, 218, 188))
    sheet.save(output, quality=94, subsampling=0)


def verify_video(ffprobe: str, video: Path) -> dict:
    raw = run_command([
        ffprobe, "-v", "error", "-count_frames", "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height,pix_fmt,r_frame_rate,avg_frame_rate,duration,nb_frames,nb_read_frames:format=duration,size",
        "-of", "json", str(video),
    ])
    probe = json.loads(raw)
    if len(probe.get("streams", [])) != 1:
        raise ValueError(f"Missing video stream: {video}")
    stream = probe["streams"][0]
    checks = {
        "h264": stream.get("codec_name") == "h264",
        "yuv420p": stream.get("pix_fmt") == "yuv420p",
        "dimensions": (stream.get("width"), stream.get("height")) == SIZE,
        "averageFrameRate": Fraction(stream.get("avg_frame_rate", "0/1")) == FPS,
        "declaredFrameRate": Fraction(stream.get("r_frame_rate", "0/1")) == FPS,
        "declaredFrames": int(stream.get("nb_frames", -1)) == FRAME_COUNT,
        "decodedFrames": int(stream.get("nb_read_frames", -1)) == FRAME_COUNT,
        "duration": abs(float(probe["format"]["duration"]) - DURATION) < 0.001,
    }
    if not all(checks.values()):
        raise ValueError(f"Portal preview failed verification: {checks}; probe={probe}")
    return {"file": video.name, "checks": checks, "ffprobe": probe}


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--animation-dir", type=Path, default=ROOT / "art" / "Graduate" / "animation")
    parser.add_argument("--ffmpeg", default="C:/ffmpeg/bin/ffmpeg.exe")
    parser.add_argument("--ffprobe", default="C:/ffmpeg/bin/ffprobe.exe")
    args = parser.parse_args(argv)
    animation_dir = args.animation_dir.expanduser().resolve()
    if not animation_dir.is_dir():
        raise FileNotFoundError(animation_dir)
    ffmpeg, ffprobe = executable(args.ffmpeg), executable(args.ffprobe)
    frames_directory = animation_dir / "portal_frames"
    frames, evidence = inspect_frames(frames_directory)
    render_report = frames_directory / "render-validation.json"
    render_summary = None
    if render_report.is_file():
        render_summary = json.loads(render_report.read_text(encoding="utf-8"))
        if render_summary.get("status") != "complete" or render_summary.get("mode") != "full":
            raise ValueError("The portal render manifest is not a completed full render")
        if render_summary.get("expectedFrames") != list(range(1, FRAME_COUNT + 1)):
            raise ValueError("The portal render manifest does not cover all 150 frames")
    with tempfile.TemporaryDirectory(prefix=".portal-preview-build-", dir=animation_dir) as stage_name:
        stage = Path(stage_name)
        video = stage / "portal_entry_preview.mp4"
        print("Encoding portal entry: 150 frames, 800x450, 30fps, 5 seconds...", flush=True)
        run_command([
            ffmpeg, "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
            "-filter_threads", "1", "-framerate", str(FPS), "-start_number", "1",
            "-i", str(frames_directory / "frame_%04d.png"),
            "-vf", "setsar=1", "-an", "-frames:v", str(FRAME_COUNT), "-r", str(FPS),
            "-c:v", "libx264", "-preset", "fast", "-crf", "20", "-pix_fmt", "yuv420p",
            "-movflags", "+faststart", "-threads", "2", str(video),
        ])
        sheet = stage / "portal_entry_contact_sheet.jpg"
        make_contact_sheet(frames, sheet)
        verified_video = verify_video(ffprobe, video)
        for frame, snapshot in zip(frames, evidence):
            current = frame.stat()
            if (current.st_size, current.st_mtime_ns) != (snapshot["sizeBytes"], snapshot["mtimeNs"]):
                raise RuntimeError(f"Source frame changed while packaging; outputs not replaced: {frame}")
        report = {
            "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
            "sourceDirectory": frames_directory.name,
            "sourceFrameCount": FRAME_COUNT, "sourceSize": list(SIZE),
            "fps": FPS, "durationSeconds": DURATION,
            "sourceFrames": evidence,
            "sourceFramesUnchangedDuringPackaging": True,
            "renderManifest": str(render_report) if render_summary else None,
            "video": verified_video,
            "contactSheet": sheet.name,
            "contactSheetSourceFrames": list(CONTACT_FRAMES),
            "visualReview": {
                "status": "not_performed_by_packaging_script",
                "required": "Review the new contact sheet and play the complete 5-second preview for the jump, portal traversal, cloth intersections, and camera framing.",
            },
        }
        report_path = stage / "portal-preview-validation.json"
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        for artifact in (video, sheet, report_path):
            destination = animation_dir / artifact.name
            artifact.replace(destination)
            print(f"Wrote {destination}", flush=True)
    print("PORTAL_PACKAGE_DONE: actual ffprobe decode verified 800x450, 30fps, 150 frames, 5 seconds.", flush=True)


if __name__ == "__main__":
    main()
