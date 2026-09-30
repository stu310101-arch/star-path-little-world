# GitHub Pages release

`game/` contains the editable Godot project. `deploy/github-pages/` contains
the exact exported browser build used by GitHub Pages. Its 176 MB Godot PCK is
stored in four parts under 50 MB each so ordinary Git can carry it; the Pages
workflow verifies SHA-256 hashes and reassembles the original file before
uploading the static site. The deployed PCK is byte-identical to `build/web/index.pck`.

To publish a later game update from the project root:

1. Export the Web preset to `build/web/index.html` using Godot 4.7.2.
2. Run `python tools/package_web_notices.py`.
3. Run `python deploy/github-pages/package.py prepare --source build/web --package deploy/github-pages`.
4. Commit and push the changed Godot source and `deploy/github-pages/` files to `main`.

The Pages workflow reconstructs and deploys the browser build on that push.
The source Blender masters for the training room and revised bank stones are
also tracked. Editor caches, local review output, prior art experiments, and
user-supplied source archives remain in the local workspace.
