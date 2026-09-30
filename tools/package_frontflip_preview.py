"""Package actual native-engine frames at their measured capture times."""
from pathlib import Path
import json
import subprocess

ROOT = Path(__file__).resolve().parents[1]
STUDIO = ROOT / "deliverables/jump/studio"
FFMPEG = Path("C:/ffmpeg/bin/ffmpeg.exe")
manifest = json.loads((STUDIO / "capture.json").read_text(encoding="utf-8"))
frames = manifest["frames"]
assert manifest["passed"] and len(frames) >= 20, "Capture did not clear physical railing"

def write_concat(rows, destination, uniform=None):
    text = []
    for index, row in enumerate(rows):
        # Paths are existing local capture files, never command fragments.
        filename = (STUDIO / row["file"]).resolve().as_posix().replace("'", "'\\''")
        text.append("file '" + filename + "'")
        duration = uniform or (max(0.01, rows[index + 1]["seconds"] - row["seconds"]) if index + 1 < len(rows) else 0.45)
        text.append(f"duration {duration:.6f}")
    text.append(text[-2])
    destination.write_text("\n".join(text) + "\n", encoding="utf-8")

timeline = STUDIO / "timeline.ffconcat"
write_concat(frames, timeline)
movie = STUDIO.parent / "frontflip-preview.mp4"
subprocess.run([str(FFMPEG), "-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(timeline), "-vf", "fps=30", "-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(movie)], check=True)
chosen = [min(frames, key=lambda row: abs(row["seconds"] - time)) for time in [0.43,0.54,0.70,0.84,1.0,1.15,1.34,1.57]]
contact_inputs = []
for row in chosen:
    contact_inputs.extend(["-i", str(STUDIO / row["file"])])
filters = ";".join(f"[{i}:v]scale=480:360[v{i}]" for i in range(8))
filters += ";" + "".join(f"[v{i}]" for i in range(8)) + "xstack=inputs=8:layout=0_0|480_0|960_0|1440_0|0_360|480_360|960_360|1440_360[out]"
sheet = STUDIO.parent / "frontflip-contact-sheet.png"
subprocess.run([str(FFMPEG), "-hide_banner", "-loglevel", "error", "-y", *contact_inputs, "-filter_complex", filters, "-map", "[out]", "-frames:v", "1", str(sheet)], check=True)
print(json.dumps({"movie": str(movie), "contact_sheet": str(sheet), "frames": len(frames), "passed": True}))
