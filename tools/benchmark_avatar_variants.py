"""Serial native avatar comparisons with Windows RSS/private-commit counters."""
import argparse
import ctypes
from ctypes import wintypes
import json
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]

class ProcessMemory(ctypes.Structure):
    _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD)] + [
        (name, ctypes.c_size_t) for name in ["PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage", "PrivateUsage"]]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--variants", nargs="+", default=["original", "runtime"])
    args = parser.parse_args()
    destination = ROOT / "deliverables/low-memory/avatar"
    destination.mkdir(parents=True, exist_ok=True)
    psapi = ctypes.WinDLL("psapi")
    get_memory = psapi.GetProcessMemoryInfo
    get_memory.argtypes = [wintypes.HANDLE, ctypes.POINTER(ProcessMemory), wintypes.DWORD]
    get_memory.restype = wintypes.BOOL
    for variant in args.variants:
        # The Windows _console executable is a launcher, not the render process.
        # Launch its GUI sibling directly so per-process counters cover the game.
        godot = args.godot.replace("godot_console.exe", "godot.exe")
        command = [godot, "--path", str(ROOT / "game"), "--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3",
                   "-d", "--ignore-error-breaks", "--script", "res://tests/avatar_variant_benchmark.gd", "--", "--variant=" + variant]
        with (destination / ("benchmark-" + variant + ".log")).open("w", encoding="utf8") as output:
            process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
            start = time.monotonic()
            samples = []
            while process.poll() is None:
                counters = ProcessMemory()
                counters.cb = ctypes.sizeof(counters)
                if get_memory(wintypes.HANDLE(int(process._handle)), ctypes.byref(counters), ctypes.sizeof(counters)):
                    samples.append({"elapsed_seconds": time.monotonic() - start, "rss_bytes": counters.WorkingSetSize,
                                    "rss_peak_bytes": counters.PeakWorkingSetSize, "private_commit_bytes": counters.PrivateUsage,
                                    "commit_peak_bytes": counters.PeakPagefileUsage})
                if time.monotonic() - start > 180:
                    process.terminate()
                    raise RuntimeError("Owned avatar benchmark timed out: " + variant)
                time.sleep(0.25)
        assert process.returncode == 0, (variant, process.returncode)
        result = {"variant": variant, "exit_code": process.returncode, "samples": samples,
                  "max_rss_bytes": max(x["rss_peak_bytes"] for x in samples),
                  "max_private_commit_bytes": max(x["private_commit_bytes"] for x in samples),
                  "max_commit_bytes": max(x["commit_peak_bytes"] for x in samples),
                  "last_rss_bytes": samples[-1]["rss_bytes"], "last_private_commit_bytes": samples[-1]["private_commit_bytes"],
                  "note": "Windows per-process memory counters, 250 ms samples. GPU dedicated/shared allocations and whole-system use are separate; these are not JS heap counters."}
        (destination / ("memory-" + variant + ".json")).write_text(json.dumps(result, indent=2), encoding="utf8")
        print(json.dumps({k: v for k, v in result.items() if k != "samples"}), flush=True)


if __name__ == "__main__":
    main()
