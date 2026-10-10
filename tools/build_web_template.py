"""Build this game's pinned single-threaded Godot Web template.

Prepare build/engine-source at Godot 4.7.2-stable and build/emsdk with the
official SDK 4.0.11 (Godot's own CI version). No global SDK activation is used.
"""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE_COMMIT = "ed1daf0bf001b61586d9930840f2f1394092c079"
MODULES = ["gdscript", "text_server_adv", "freetype", "msdfgen", "regex", "ogg", "vorbis", "mp3",
           "godot_physics_3d", "jolt_physics", "meshoptimizer", "basis_universal", "bcdec", "etcpak", "jpg", "webp", "mbedtls"]

def main():
    source = ROOT / "build/engine-source"
    sdk = ROOT / "build/emsdk"
    git = os.environ.get("GIT_EXE", "git")
    assert subprocess.check_output([git, "rev-parse", "HEAD"], cwd=source, text=True).strip() == SOURCE_COMMIT
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1", EMSDK=str(sdk))
    env["EMSDK_NODE"] = str(sdk / "node/24.19.0_64bit/node.exe")
    env["EMSDK_PYTHON"] = sys.executable
    env["PATH"] = os.pathsep.join([str(sdk / "upstream/emscripten"), str(sdk), str(Path(sys.executable).parent), env.get("PATH", "")])
    command = [sys.executable, "-m", "SCons", "platform=web", "target=template_release", "threads=no", "arch=wasm32",
               "optimize=size", "lto=thin", "debug_symbols=no", "modules_enabled_by_default=no", "-j6"]
    command.extend("module_" + name + "_enabled=yes" for name in MODULES)
    with (ROOT / "build/web-template-build.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(command, cwd=source, env=env, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError("Template compile failed; see build/web-template-build.log")
    print("Template built with preserved 3D, physics, Chinese shaping, audio, font, image and network support.")

if __name__ == "__main__":
    main()
