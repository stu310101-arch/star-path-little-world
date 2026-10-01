# GitHub Pages release

`game/` contains the editable Godot project. `deploy/github-pages/` contains
the exact exported browser build used by GitHub Pages. The boot PCK is stored
in parts under 50 MB; deferred packs retain their content-addressed filenames
under `files/packs/`. The Pages workflow verifies every SHA-256 and reassembles
the boot PCK before uploading the static site. All published files must match
`build/web/`, including `index.packs.json` and its deferred files.

To publish a later game update from the project root:

1. Run `python tools/build_web_release.py --godot <Godot-4.7.2-console-path>`.
   Add `--rebuild-world` after changing generated geometry/material sources.
   This exports Web, enumerates dependencies, splits packs, validates all imports
   from an isolated directory, writes notices/release hashes, prepares and assembles.
2. Test the assembled `_site/` on localhost. A successful source test does not
   verify Web HTTP downloads, shader compilation or the packaged resource graph.
3. Commit and push the changed source, generation tools/output and
   `deploy/github-pages/` files to `main`.

Do not publish a plain Godot export without the split step: it is a valid but
monolithic build and would restore the large initial download. Hash filenames
prevent mixing pack versions; this does not add persistent browser caching.

The Pages workflow reconstructs and deploys the browser build on that push.
The source Blender masters for the training room and revised bank stones are
also tracked. Editor caches, local review output, prior art experiments, and
user-supplied source archives remain in the local workspace.
