# Embedded Windows webview

Godot WRY v1.0.2, https://github.com/doceazedo/godot_wry/releases/tag/v1.0.2
MIT license (see LICENSE). Uses the installed Microsoft Edge WebView2 Runtime.

Downloaded upstream release archive:
https://github.com/doceazedo/godot_wry/releases/download/v1.0.2/godot_wry.zip

Archive SHA256: `706b407aca47df0626df26997a3e825a49c91985a199cead3d0b75d35fca783c`
Windows x64 DLL SHA256: `a8fb72d3570708874f92e5e55384c35127c056c1554eb7a06b5997d050831e5b`

Only the unmodified Windows x64 DLL and icon are vendored. WRY.gdextension
selects Windows x64, disables hot reload and omits unshipped platforms/examples.
Web presets exclude this addon. No external browser process is launched to play Go.
The view reads packaged res:// HTML; its separate user:// profile retains matches.

API documentation: https://godot-wry.doce.sh/reference/webview.html
Source: https://github.com/doceazedo/godot_wry/tree/v1.0.2/rust
