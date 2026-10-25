# Road vehicles

Original editable vehicle geometry, authored in meters in Blender 5.2. No vendor car meshes are modified or embedded.

- Source: `RoadVehicles.blend`; reproducible authoring: `tools/author_road_vehicles.py`.
- Export: `game/assets/vehicles/{sedan,hatchback,suv}.glb` plus `_lod1.glb`.
- Blender forward is -Y; Godot forward is +Z. Model origin is the tire-contact plane. The four `wheel-*` pivots rotate around local X.
- Sedan: 4.62 m nominal body length, 1.82 m body width, 1.45 m roof height. Hatchback: 4.08 / 1.79 / 1.51 m. SUV: 4.60 / 1.89 / 1.71 m. Mirrors and bumper details extend beyond nominal body dimensions; full imported bounds are recorded in the manifest.
- All three LOD0 files total 77,154 triangles; LOD1 totals 38,576. The source retains the live wheel-well cuts and individual trim geometry; decimation and joining are applied only to export copies.
- Standard glTF metallic-roughness materials retain paint, rubber, alloy, reflective smoked glass and light lenses in the game's Compatibility renderer. Dark glass is intentionally opaque; there is no cabin interior.

Regenerate with Blender background mode: `blender --background --python tools/author_road_vehicles.py`. This writes GLBs, the manifest, the editable master and seven Cycles review renders under `deliverables/vehicles/`.

Run Godot `tests/vehicle_asset_checks.gd` after importing, and `tests/vehicle_world_checks.gd` after rebuilding the world. `tools/capture_vehicles.gd` reviews actual imported assets using native rendering; `tools/capture_vehicles_world.gd` reviews the deployed traffic using the production world's lighting and geometry.
