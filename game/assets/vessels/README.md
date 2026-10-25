# Authored vessel kit

Original project assets made in Blender 5.2.2. No downloaded meshes, textures,
people, or source scenery models are incorporated.

| Asset | Hull length | Role |
| --- | ---: | --- |
| fishing_boat.glb | 7.8 m | Harbor work launch, wheelhouse, hauling winch and outboard |
| tugboat.glb | 17 m | Raised bridge, engine house, towing winch and heavy fenders |
| liner.glb | 36 m | Two passenger decks, aft seating, companionways and life rafts |

Godot coordinates: +Y up, +Z bow. Origin lies at the waterline, centered on the
hull plan; the work launch's outboard extends behind that plan. Use metre scale.
The boats have no walkable collision because their current role is moving
offshore scenery and moored harbor scenery.

Editable source: `art/Vessels/vessels-source.blend`. The three source collections
are laid out separately along X for editing; their `export_layout_offset_x`
metadata records the display offset. Export copies retain the waterline origin.
Procedural source: `tools/build_vessels.py`; run using Blender in background mode.
The generator evaluates bevels and joins export copies only. Source components
and modifiers remain editable.

The kit uses 11 shared PBR materials, without external image textures. Curved
hulls have separate painted topsides, rubber boot lines and antifouling surfaces.
Window glass is inset into open window bays and framed with gasket geometry.
Cloth-like transparencies and transmission are intentionally unnecessary in
the project's GL Compatibility renderer.

Validation: `art/Vessels/validation.json`, `game/tests/vessel_asset_checks.gd`.
Actual Blender and Godot bow/stern renders: `deliverables/vessels/`.
`game/tools/capture_vessels.gd` recreates the Godot inspection views.
