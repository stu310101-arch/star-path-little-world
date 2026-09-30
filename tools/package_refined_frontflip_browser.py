"""Package reviewed WebGL screenshots at their exact 60 Hz physics times.

Run only after browser-review/capture.json is complete. Every adjacent capture
must be two physics ticks apart, so one screenshot is exactly one 30 FPS frame.
No wall-clock capture delay, interpolation, or speed adjustment is introduced.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import tempfile
from fractions import Fraction
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "deliverables/frontflip-refined/browser-review/capture.json"
FPS = 30
PHYSICS_HZ = 60


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output-dir", type=Path)
    parser.add_argument("--ffmpeg", type=Path, default=Path("C:/ffmpeg/bin/ffmpeg.exe"))
    parser.add_argument("--ffprobe", type=Path, default=Path("C:/ffmpeg/bin/ffprobe.exe"))
    parser.add_argument("--width", type=int, default=960)
    parser.add_argument("--height", type=int, default=720)
    return parser.parse_args()


def run(command: list[str], timeout: int = 180) -> str:
    result = subprocess.run(command, check=True, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=timeout)
    return result.stdout


def load_sequences(manifest: Path) -> list[dict]:
    content = json.loads(manifest.read_text(encoding="utf-8-sig"))
    sequences = content.get("sequences", [])
    if len(sequences) != 2 or {row.get("sequence") for row in sequences} != {"standing", "moving"}:
        raise ValueError("Manifest must contain one standing and one moving sequence")
    result = []
    for sequence in sorted(sequences, key=lambda row: row["sequence"] != "standing"):
        if sequence.get("passed") is not True:
            raise ValueError(f"Capture has not passed: {sequence['sequence']}")
        frames = sequence.get("frames", [])
        if len(frames) < 30:
            raise ValueError(f"Too few captured frames: {sequence['sequence']}")
        previous_tick = None
        prepared = []
        for frame in frames:
            tick = frame.get("tick")
            if isinstance(tick, bool) or not isinstance(tick, int) or tick < 0:
                raise ValueError(f"Invalid physics tick: {tick!r}")
            if previous_tick is not None and tick != previous_tick + 2:
                raise ValueError(f"Missing/out-of-order 30 FPS capture between ticks {previous_tick} and {tick}")
            if "seconds" in frame and abs(float(frame["seconds"]) - tick / PHYSICS_HZ) > 0.001:
                raise ValueError(f"Frame seconds disagree with tick/60 at tick {tick}")
            source = Path(frame["file"])
            source = source.resolve() if source.is_absolute() else (manifest.parent / source).resolve()
            if not source.is_file():
                raise FileNotFoundError(source)
            with Image.open(source) as pixels:
                # CUA may return JPEG bytes even when the saved filename ends
                # in .png. Read the actual format; never rewrite the capture.
                image_format = pixels.format
                if image_format not in {"PNG", "JPEG"}:
                    raise ValueError(f"Unsupported screenshot format {image_format}: {source}")
                pixels.verify()
            prepared.append({**frame, "path": source, "tick": tick, "seconds": tick / PHYSICS_HZ,
                             "image_format": image_format})
            previous_tick = tick
        if len({frame["image_format"] for frame in prepared}) != 1:
            raise ValueError(f"Mixed screenshot encodings in {sequence['sequence']}")
        result.append({**sequence, "frames": prepared})
    return result


def encode(sequence: dict, destination: Path, args: argparse.Namespace) -> None:
    # image2pipe receives exactly one original screenshot per 1/30 s. This also
    # avoids concat-demuxer image time-base rounding and filename escaping.
    video_filter = (
        f"scale={args.width}:{args.height}:force_original_aspect_ratio=decrease:flags=lanczos,"
        f"pad={args.width}:{args.height}:(ow-iw)/2:(oh-ih)/2:color=0x18252b,setsar=1"
    )
    input_codec = "png" if sequence["frames"][0]["image_format"] == "PNG" else "mjpeg"
    command = [str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-y",
               "-f", "image2pipe", "-framerate", str(FPS), "-vcodec", input_codec, "-i", "pipe:0",
               "-an", "-vf", video_filter, "-frames:v", str(len(sequence["frames"])),
               "-c:v", "libx264", "-threads", "2", "-preset", "medium", "-crf", "20",
               "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(destination)]
    with tempfile.TemporaryFile() as error_stream:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                   stderr=error_stream)
        try:
            assert process.stdin is not None
            for frame in sequence["frames"]:
                process.stdin.write(frame["path"].read_bytes())
            process.stdin.close()
            exit_code = process.wait(timeout=180)
        except BaseException:
            process.kill()
            process.wait(timeout=15)
            error_stream.seek(0)
            diagnostics = error_stream.read().decode("utf-8", "replace")
            if diagnostics:
                print(diagnostics, flush=True)
            raise
        error_stream.seek(0)
        diagnostics = error_stream.read().decode("utf-8", "replace")
        if exit_code or diagnostics.strip():
            raise RuntimeError(f"Encoding {destination.name} failed: {diagnostics}")


def verify_video(path: Path, expected_frames: int, args: argparse.Namespace) -> dict:
    probe = json.loads(run([str(args.ffprobe), "-v", "error", "-select_streams", "v:0",
                           "-count_frames", "-show_entries",
                           "stream=codec_name,width,height,avg_frame_rate,nb_read_frames,duration:format=duration",
                           "-of", "json", str(path)]))
    stream = probe["streams"][0]
    actual_frames = int(stream["nb_read_frames"])
    duration = float(stream.get("duration", probe["format"]["duration"]))
    if (stream["codec_name"] != "h264" or Fraction(stream["avg_frame_rate"]) != FPS
            or actual_frames != expected_frames or stream["width"] != args.width
            or stream["height"] != args.height
            or abs(duration - expected_frames / FPS) > 0.002):
        raise ValueError(f"Unexpected encoded video metadata for {path.name}: {probe}")
    run([str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-xerror", "-err_detect", "explode", "-i", str(path),
         "-map", "0:v:0", "-f", "null", "-"])
    return {"file": str(path), "frames": actual_frames, "fps": FPS,
            "duration_seconds": duration, "width": args.width, "height": args.height,
            "full_decode_passed": True, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def phase(frame: dict) -> str:
    status = frame.get("status", {})
    if not isinstance(status, dict):
        # The browser's review HUD is also a valid status value. Keep its
        # animation phase, not command/render counters, in compact captions.
        match = re.search(r"\b(JumpStart|JumpAir|JumpLand|Idle|Walk|Run)\b", str(status))
        return match.group(1) if match else ""
    return str(status.get("jump_state", status.get("state", status.get("phase", status.get("clip", "")))))


def key_frames(sequence: dict) -> list[dict]:
    frames = sequence["frames"]
    first_tick = frames[0]["tick"]
    anticipation = next((row["tick"] for row in frames if phase(row).lower() in {"anticipation", "jumpstart"}),
                        first_tick + 12)
    airborne = next((row["tick"] for row in frames if phase(row).lower() in {"airborne", "jumpair"}),
                   anticipation + 14)
    landing = next((row["tick"] for row in frames if phase(row).lower() in {"landing", "jumpland"}),
                   airborne + 44)
    targets = [first_tick, anticipation + 4, anticipation + 12,
               airborne + 6, airborne + 18, airborne + 30]
    targets += [landing + value for value in [0, 12, 30, 48, 68]]
    targets += [frames[-1]["tick"]]
    return [min(frames, key=lambda row: abs(row["tick"] - wanted)) for wanted in targets]


def contact_sheet(sequence: dict, destination: Path) -> dict:
    rows = key_frames(sequence)
    tile_width, picture_height, label_height, header_height = 420, 315, 42, 46
    canvas = Image.new("RGB", (tile_width * 4, (picture_height + label_height) * 3 + header_height), "#18252b")
    draw = ImageDraw.Draw(canvas)
    font_path = Path("C:/Windows/Fonts/arial.ttf")
    font = ImageFont.truetype(str(font_path), 18) if font_path.exists() else ImageFont.load_default()
    small = ImageFont.truetype(str(font_path), 15) if font_path.exists() else ImageFont.load_default()
    draw.text((14, 14), f"Actual Godot WebGL | {sequence['sequence']} | {sequence.get('view', '')} | 60 Hz physics",
              font=font, fill="#eee4cc")
    for index, frame in enumerate(rows):
        x = index % 4 * tile_width
        y = index // 4 * (picture_height + label_height) + header_height
        with Image.open(frame["path"]) as pixels:
            thumbnail = ImageOps.contain(pixels.convert("RGB"), (tile_width, picture_height), Image.Resampling.LANCZOS)
            canvas.paste(thumbnail, (x + (tile_width - thumbnail.width) // 2,
                                     y + (picture_height - thumbnail.height) // 2))
        draw.text((x + 10, y + picture_height + 5),
                  f"tick {frame['tick']:03d} | {frame['seconds']:.3f} s | {phase(frame)}", font=small, fill="#eee4cc")
    canvas.save(destination)
    return {"file": str(destination), "ticks": [frame["tick"] for frame in rows]}


def concat_line(path: Path) -> str:
    return "file '" + path.resolve().as_posix().replace("'", "'\\''") + "'\n"


def main() -> None:
    args = arguments()
    args.manifest = args.manifest.resolve()
    output = (args.output_dir or args.manifest.parent.parent).resolve()
    if args.width <= 0 or args.height <= 0 or args.width % 2 or args.height % 2:
        raise ValueError("H.264 output width and height must be positive even integers")
    for executable in (args.ffmpeg, args.ffprobe):
        if not executable.is_file():
            raise FileNotFoundError(executable)
    sequences = load_sequences(args.manifest)
    output.mkdir(parents=True, exist_ok=True)
    videos, sheets, timeline = [], [], []
    for sequence in sequences:
        movie = output / f"{sequence['sequence']}-frontflip.mp4"
        encode(sequence, movie, args)
        evidence = verify_video(movie, len(sequence["frames"]), args)
        evidence.update({"sequence": sequence["sequence"], "view": sequence.get("view", ""),
                         "source_image_format": sequence["frames"][0]["image_format"],
                         "first_tick": sequence["frames"][0]["tick"], "last_tick": sequence["frames"][-1]["tick"]})
        videos.append(evidence)
        timeline.append(concat_line(movie))
        sheets.append(contact_sheet(sequence, output / f"{sequence['sequence']}-frontflip-contact-sheet.png"))
    combined_list = output / "frontflip-refined-preview.ffconcat"
    combined_list.write_text("ffconcat version 1.0\n" + "".join(timeline), encoding="utf-8")
    combined_path = output / "frontflip-refined-preview.mp4"
    run([str(args.ffmpeg), "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0",
         "-i", str(combined_list), "-c", "copy", "-movflags", "+faststart", str(combined_path)])
    combined = verify_video(combined_path, sum(row["frames"] for row in videos), args)
    combined_sheet_path = output / "frontflip-refined-contact-sheet.png"
    sheet_images = [Image.open(row["file"]).convert("RGB") for row in sheets]
    combined_sheet = Image.new("RGB", (max(pixels.width for pixels in sheet_images),
                                        sum(pixels.height for pixels in sheet_images)), "#18252b")
    offset = 0
    for pixels in sheet_images:
        combined_sheet.paste(pixels, (0, offset))
        offset += pixels.height
        pixels.close()
    combined_sheet.save(combined_sheet_path)
    report = {"passed": True, "manifest": str(args.manifest), "physics_hz": PHYSICS_HZ, "fps": FPS,
              "timing": "Each screenshot spans exactly two physics ticks; no wall-clock capture delay is used.",
              "videos": videos, "combined": combined, "contact_sheets": sheets,
              "combined_contact_sheet": str(combined_sheet_path)}
    report_path = output / "browser-preview-package.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": True, "report": str(report_path), "combined": str(combined_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
