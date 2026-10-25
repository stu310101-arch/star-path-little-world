# Indoor export cleanup — 2026-10-20

This pass removes invisible geometry and enables conservative backface culling
in the shared indoor assets used by every graphics profile. It does not change
resolution, antialiasing, shadows, textures, visible vertex positions, collision,
interaction targets, or editable Blender sources.

## Measured asset changes

| Runtime asset | Triangles before | After | Removed |
| --- | ---: | ---: | ---: |
| Admissions studio | 111,744 | 111,602 | 142 buried foundation faces |
| Training startup scene | 64,517 | 57,160 | 7,357 |
| Training fully loaded detail meshes | 131,513 | 123,436 | 8,077 |
| University atrium | 286,892 | 286,892 | 0 |
| University gallery shell | 306,549 | 306,549 | 0 |
| University exhibit kit | 259,392 | 259,382 | 10 exact zero-area faces |
| University feature book | 648 | 648 | 0 |

Training startup and detail are alternatives: the detail meshes replace the
startup meshes. Their combined reduction of 15,434 triangles is an asset total,
not a single-frame saving. Fully loaded room geometry decreases by about 6.14%;
startup geometry by about 11.40%. Each version removes 3,780 buried tile faces;
the remainder are exactly zero-area triangles. The separately loaded Furina
figure and its hair/cutout materials are unchanged.

Eligible opaque, closed surfaces now use backface culling. The GLB material
counts changed are 16 in admissions, 9 in atrium, 9 in gallery, 10 in the exhibit
kit, and 4 in the feature book. Training changes three surfaces per version.
This does not halve triangle counts or guarantee a particular FPS increase:
it prevents back-facing fragments from being rasterized. Blender exports can
default to disabled culling, as explained in the
[Godot standard material documentation](https://docs.godotengine.org/en/latest/tutorials/3d/standard_material_3d.html).

## Safety rules and evidence

`tools/optimize_indoor_geometry.py` implements the shared rules:

- Remove triangles only when their computed area is exactly zero, or when the
  same indexed triangle with the same winding repeats in the same surface.
  Small nonzero triangles, different attribute indices, reversed winding and
  coincident faces in separate materials are retained.
- Admissions foundation removal applies only to `SM_Admissions_Architecture`
  within the authored foundation footprint and strictly below `y=-0.025`.
  The continuous foundation top is `y=-0.02`; slabs, bevels visible in seams,
  and the garden seen through the windows remain intact.
- Training buried-face removal applies only to
  `SM_Architecture_Limestone` and `SM_Architecture_Limestone_Alternate`,
  strictly below `y=-0.015`. The actual removed faces range from
  `y=-0.0275` to `y=-0.02050061`. The continuous structural plinth above them
  ends at `y=-0.01` and is retained, including the surface visible in seams.
  `tools/build_training_room.py:154–157` defines that plinth and the tiles.
  The playable camera is clamped to `y>=0.40`; screenshots also inspect that
  lowest camera level. The entry platform is excluded.
- Before any buried-face removal, each candidate surface is welded by **exact
  positions for analysis only**, then checked for two oppositely oriented faces
  per edge and positive enclosed volume in every connected component.
  Geometry itself is never welded or decimated.
- Culling applies only when every surface using a shared material passes.
  Transparent materials and names indicating glass, foliage, hair, water,
  screens or optical effects are excluded. Open or inconsistent surfaces retain
  their original culling.

`game/tools/indoor_runtime_optimizer.gd` operates on the actual training startup
scene and generated `.res` meshes. It verifies that these static meshes have no
blend shapes, bones, generated LODs, or shadow meshes before proceeding. It
preserves Godot's original encoded vertex and attribute buffers and modifies
only index buffers and eligible material culling. Every vertex, normal, UV and
tangent attribute is compared byte-for-byte after reconstruction. Resource
transforms and scene ownership are retained.

## Rebuild and verification

The cleanup is called after exports in:

- `tools/build_admissions_studio.py`
- `tools/build_university_hall.py`
- `art/UniversityHall/build_exhibit_kit.py`
- `game/tools/build_training_room_runtime.gd`

Standalone commands from the repository root:

```powershell
python tools/optimize_indoor_geometry.py --dry-run
python tools/optimize_indoor_geometry.py
Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tools/optimize_indoor_runtime.gd -- --dry-run
Godot_v4.7.2-stable_win64_console.exe --headless --path game --script res://tools/optimize_indoor_runtime.gd
python -m unittest discover -s tools -p test_indoor_geometry_optimizer.py -v
```

Verification completed on Godot 4.7.2 / native Compatibility / RX 5700 XT:

- Eight focused rule tests cover winding, open geometry, cutout exclusions,
  exact degeneracy, attribute seams, tiny valid faces and both floor guards.
- Actual training resource cleanup and attribute-preservation assertions passed.
- Five GLBs reimported successfully, preserving the university texture-sharing
  import hook and generated LOD behavior.
- A second dry run found zero additional deletions or culling changes for all
  five GLBs and both training versions.
- `game/tests/indoor_geometry_visual_checks.gd` captured 21 production-rendered
  views: room entry, ceiling, lowest floor view, furniture sides, atrium and
  gallery. All 21 images were reviewed; no cleanup-induced holes were found.
- `admissions_seat_integration_checks.gd --capture` passed 86 checks. All eight
  seated captures were reviewed, including desk sides and sofa views.

Local evidence is under `deliverables/graphics-performance/`:
`indoor-audit.json`, `indoor-optimization.json`, `training-optimization.json`,
the final `*-dry-run.json`, and `indoor-visual/report.json` with 21 PNGs.
Per-file source/output SHA-256 values are in the optimization reports.
Eight additional seat captures are in `deliverables/admissions-room/seats/`.
These are geometry and visual checks, not a claim of measured mobile FPS,
temperature or battery behavior.

## Source size versus rendering cost

The GLB patch appends replacement index slices while leaving all original
attribute/image bytes intact. Old unreferenced slices remain in the source
container: admissions GLB grows from 12,378,252 to 12,654,220 bytes, and the kit
from 34,601,868 to 34,609,892 bytes. This pass does **not** claim smaller downloads.
Godot imports only referenced indices; the training resources retain identical
vertex buffers and smaller index buffers. Final runtime GPU-memory and frame
measurements belong to the common route benchmark.

## Existing safeguards and future opportunities

The outdoor world is detached from the scene tree when entering an interior,
so it is not secretly rendered behind the room. University `clear_space()`
removes the previous atrium/gallery; all 138 schools are not drawn at once.
Only the current eight exhibits enter the scene tree.

University texture files include duplicate exported PNG copies, but
`palette_import.gd` already binds materials to canonical shared textures.
Duplicate source bytes therefore do not establish duplicate GPU allocations.

The large university architecture mesh remains a future spatial-culling
opportunity: its single room-sized AABB cannot reject individual bookcases.
Splitting along real visibility boundaries could reduce unseen submissions,
but increases draw calls and requires comparable-route measurements. This pass
does not hide visible shelves, whole galleries, windows, or distant exhibits
merely to improve a counter.
