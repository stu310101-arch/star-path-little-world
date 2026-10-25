# 採光書房／落點分析室

Editable master: `AdmissionsStudio.blend`. Rebuild with Blender 5.2.2 LTS using `tools/build_admissions_studio.py`; `-- --no-render` skips review renders. The builder authors furniture at metre scale and retains bevel modifiers in the source. Evaluated export copies are merged into seven spatial zones; the editable objects are not destroyed.

The room reuses the project's original university-library walnut, stone, plaster, leather and paper PBR maps. The builder reduces image copies to 512 px without overwriting those source textures. There are no downloaded or externally generated assets. Material-scale planar UVs deliberately repeat shared textures, and walnut grain follows the long edge of each part.

The GLB embeds its images. Godot extracts `admissions_studio_*.png` during import; these are required dependencies of this model, unlike the older university-hall duplicate images replaced by its custom importer. Keep their import sidecars, mipmaps and the scene's automatic mesh LOD generation enabled.

`layout.json` uses Godot Y-up metres. It supplies collision proxies, six functional stations and eight seat anchors. Camera-only collision uses layer 256; furniture uses layer 1. Seat anchors identify the cushion top and a separate clear standing point. Tea is decorative; no tea interaction or drinking animation is included.

Runtime lighting, labels, camera and interaction belong to `game/scripts/admissions_room.gd` and its helpers. Blender renders are material reviews; the actual Godot captures and checks in `deliverables/admissions-room/` are the gameplay acceptance evidence. The room and its website load on demand rather than during world startup.
