# Little World Web template

This single-threaded release template is built from unmodified official Godot
4.7.2-stable commit `ed1daf0bf001b61586d9930840f2f1394092c079`, using the official
Emscripten SDK 4.0.11 and SCons 4.11.1. The source and SDK are build inputs,
not additional game runtime dependencies.

Committed ZIP SHA-256: `45f57675f1dbb657bc9f484f8841c4c58a029e894555d45662c4d1df496e611a`.
The ZIP is 8,813,227 bytes; its uncompressed WASM is 34,245,266 bytes.

`tools/build_web_template.py` records the exact enabled modules and compiler
options (`optimize=size`, `lto=thin`, `threads=no`, no debug symbols). It retains
3D, both 3D physics engines, Chinese shaping, fonts, audio, image decoders,
compression and TLS. The Web project selects Dummy for its unused 2D physics
server; native settings are preserved.

To rebuild on Windows, clone Godot at that commit into `build/engine-source`,
clone the official emsdk into `build/emsdk`, install/activate SDK 4.0.11 there,
install SCons into the Python environment, and run `python tools/build_web_template.py`.
The SDK Node path in the script is explicit; adjust it if the SDK's downloaded
Node version changes. Copy the resulting `bin/godot.web.template_release.wasm32.nothreads.zip`
to `tools/templates/little-world-web-4.7.2.zip` after inspecting and validating it.
The loader hash allowlist in `prepare_web_delivery.py` must be reviewed for a
new template; unknown loaders deliberately fail the build.

The delivery step applies the separately tested viewport/scissor restoration
patch to the generated loader, not to the engine sources. Runtime notices are
packaged by `package_web_notices.py`; Godot and its third-party license notices
remain in the published site.

Sources: [Godot 4.7.2](https://github.com/godotengine/godot/tree/4.7.2-stable),
[Emscripten SDK](https://github.com/emscripten-core/emsdk),
[Web compilation](https://docs.godotengine.org/en/stable/engine_details/development/compiling/compiling_for_web.html).
