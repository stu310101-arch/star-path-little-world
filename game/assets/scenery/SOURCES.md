# Additional scenery sources and modifications

- Kenney, Watercraft Kit 2.1, CC0: https://kenney.nl/assets/watercraft-kit
  Download: https://kenney.nl/media/pages/assets/watercraft-kit/a335cfed49-1713519620/kenney_watercraft-pack.zip
  Kept archive and License.txt under assets/source/marine. Derived tugboat, liner and rowboat are normalized and adjusted in Blender; the rowboat has a new seated angler, hat and fishing rod.
- Quaternius, Animated Fish, CC0: https://opengameart.org/content/animated-fish
  Author listing: https://quaternius.itch.io/lowpoly-animated-fish
  Download: https://opengameart.org/sites/default/files/Animated%20Fish%20Pack%20by%20%40Quaternius.zip
  Fish1 and Fish2 static OBJ meshes were normalized and given matte materials in Blender. The spherical-world leap animation is authored in ocean_life.gd; it does not claim to use the source swimming rig.
- Sakura models and seated angler: original geometry authored for this project in tools/prepare_scenery_blender.py. Three tree silhouettes; individual editable .blend files in art/WorldScenery. Runtime petals use instancing.

Rebuild with Blender 5.2 in a separate background process; original source archives remain unchanged. Godot uses game/assets/scenery/*.glb. License copies are stored beside them.

## Sakura refinement — 2026-09-24

The original faceted crowns are superseded by `tools/refine_sakura_blender.py`:
curved branching trunks, three tree variants, 312 curved botanical sprig cards per tree, and a curved isolated falling petal. Editable masters are `art/WorldScenery/sakura_refined_0.blend` through `_2.blend` and `sakura_petal.blend`; earlier masters remain intact.

`sakura-atlas.png` is original project artwork generated with the image generation tool on 2026-09-24. It contains three botanical flower sprigs and one petal on a true alpha background, showing five petals, notched tips, stamens and veins. It is not represented as a downloaded CC0 asset. The original tool output is retained under the Codex generated-images folder, with the runtime copy in this folder.

Godot uses alpha cutout, double-sided flower surfaces and explicit bark vertex colors. The garden has 14 deliberately spaced trees, 128 drifting petals and 180 settled petals. Its wooden bridge has a walkable deck, rail collision and approaches at both ends. Rebuild the refined trees after running the older marine/base scenery script, then import and rebuild the world.
