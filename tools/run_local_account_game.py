"""Run the real Godot login gate against an already-started local emulator host.

No production config, cloud service, exported build, or account data is changed.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urlsplit
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]


def local_origin(value: str) -> str:
    parsed = urlsplit(value)
    if (parsed.scheme != "http" or parsed.hostname not in ("localhost", "127.0.0.1")
            or parsed.username or parsed.password or parsed.path or parsed.query or parsed.fragment
            or parsed.port is None or not 1 <= parsed.port <= 65535
            or value != f"http://{parsed.hostname}:{parsed.port}"):
        raise ValueError("The development host must be exactly http://127.0.0.1:PORT or http://localhost:PORT")
    return value


def read_json(url: str) -> dict:
    with urlopen(url, timeout=5) as response:
        return json.load(response)


def verify_services(origin: str) -> None:
    config = read_json(origin + "/admissions/firebase-config.json")
    if config.get("useEmulators") is not True or config.get("projectId") != "demo-starpath-tests":
        raise RuntimeError("Local preview is not in emulator mode. Start it with STARPATH_EMULATORS=1.")
    services = read_json("http://127.0.0.1:4400/emulators")
    for name, port in (("auth", 9099), ("firestore", 8080)):
        entry = services.get(name, {})
        if entry.get("host") not in ("127.0.0.1", "localhost", "::1") or entry.get("port") != port:
            raise RuntimeError(f"Expected local {name} emulator on port {port}")
    with urlopen(origin + "/admissions/host/?platform=native&view=account", timeout=5) as response:
        if response.status != 200:
            raise RuntimeError("Local host route is unavailable")


def find_godot() -> Path:
    from_path = shutil.which("godot") or shutil.which("godot4")
    if from_path:
        return Path(from_path)
    packages = Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Packages"
    candidates = sorted(packages.glob("GodotEngine.GodotEngine_*/Godot_v4.7.2-stable_win64_console.exe"))
    if not candidates:
        raise RuntimeError("Pass --godot with the path to the installed Godot 4.7.2 executable")
    return candidates[0]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", default="http://127.0.0.1:4317")
    parser.add_argument("--godot", type=Path)
    parser.add_argument("--check-only", action="store_true")
    parser.add_argument("--smoke-test", choices=("login", "garden"), help="Run real local-emulator UI/IPC checks with a disposable account")
    args = parser.parse_args()
    origin = local_origin(args.origin)
    verify_services(origin)
    print(f"Local Auth + Firestore emulator host ready: {origin}/admissions/host/", flush=True)
    if args.check_only:
        return
    engine = args.godot or find_godot()
    version = subprocess.check_output([str(engine), "--version"], text=True).strip()
    if not version.startswith("4.7.2"):
        raise RuntimeError(f"Expected Godot 4.7.2; found {version}")
    environment = os.environ.copy()
    environment["STARPATH_DEV_HOST_ORIGIN"] = origin
    command = [str(engine), "--path", str(ROOT / "game")]
    if args.smoke_test:
        command += ["--script", "res://tests/local_login_gate_checks.gd"]
        if args.smoke_test == "garden":
            command += ["--", "--garden"]
        print("Running actual local signup, identity, host IPC and signout checks.", flush=True)
    else:
        print("Starting the normal login entry. Create a local test account and choose an identity.", flush=True)
    raise SystemExit(subprocess.call(command, env=environment))


if __name__ == "__main__":
    main()
