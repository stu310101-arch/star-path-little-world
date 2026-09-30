"""Remove an unused image-editor reference inherited from the source model."""
import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'Graduate'
used={n.image for m in bpy.data.materials if m.node_tree for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
removed=[]
for img in list(bpy.data.images):
    if img.source=='FILE' and img not in used and not img.packed_file and img.filepath and not Path(bpy.path.abspath(img.filepath)).is_file():
        removed.append(img.name)
        bpy.data.images.remove(img,do_unlink=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate.blend'))
missing=[img.filepath for img in bpy.data.images if img.source=='FILE' and not img.packed_file and img.filepath and not Path(bpy.path.abspath(img.filepath)).is_file()]
info=json.loads((OUT/'model-info.json').read_text(encoding='utf-8'))
info['missing_external_images']=missing
info['removed_unused_legacy_images']=removed
(OUT/'model-info.json').write_text(json.dumps(info,indent=2),encoding='utf-8')
print(json.dumps({'missing_images':missing,'removed_unused_images':removed,'saved':bpy.data.filepath}))
