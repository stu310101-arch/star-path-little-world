# Temperate tree sources

`TemperateTrees.blend` is the editable master for the rebuilt alder, birch, pine and willow. `tools/author_vegetation.py` regenerates the branch meshes, bent foliage sprays, original bark colour/normal maps and original leaf atlases. No outside geometry or texture sources are used for these four trees.

The trees export in metres with Godot +Y up and a ground-level root. The main trunk continues 0.16 m below ground; no oversized exposed roots are modeled. Broadleaf trees use primary limbs, secondary branches and tapering terminal twigs; pine has needle-bearing radial boughs; willow has hanging terminal shoots. The source preserves separate bark and foliage meshes.

Each exported tree has two material surfaces and fewer than 12,000 triangles. Exact dimensions and triangle counts are in `manifest.json` and `game/assets/vegetation_rebuilt/manifest.json`. All foliage uses a double-sided alpha mask with cutoff 0.5. The generator explicitly preserves MASK in glTF because Blender's Dithered setting otherwise exports BLEND. Bark uses standard glTF colour and tangent normal textures; no Blender-only nodes are required in Godot.

Blender review renders are under `deliverables/vegetation/`. Native Godot imported-asset renders are under `deliverables/vegetation/native/`. `game/tests/vegetation_asset_checks.gd` checks actual imported geometry, dimensions, root width, textures, alpha mode and draw-surface budgets. The other ecology authoring tool owns the separate fern/cattail source files and `understory-manifest.json`.
