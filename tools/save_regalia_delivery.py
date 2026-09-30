"""Save the validated loaded regalia candidate as the authoring master."""
from pathlib import Path
import bpy,json,shutil,hashlib
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art/Graduate'
source=bpy.data.filepath
scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
assert scene.frame_end==120 and scene.render.fps==56
bpy.context.window.scene=scene
scene.frame_set(1)
scene.sync_mode='AUDIO_SYNC'
layout=bpy.data.workspaces.get('Layout')
if layout:bpy.context.window.workspace=layout
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            space.overlay.show_overlays=False
            space.shading.type='SOLID'
            space.shading.color_type='MATERIAL'
            space.region_3d.view_perspective='CAMERA'
for obj in scene.objects:obj.select_set(False)
bpy.context.preferences.filepaths.save_version=0
master=OUT/'Male_Graduate_GameReady.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(master))
shutil.copy2(master,OUT/'Male_Graduate_Idle_Faster.blend')
data={'source_candidate':source,'master':str(master),'sha256':hashlib.sha256(master.read_bytes()).hexdigest(),'fps':56,'frames':120,'seconds':120/56,'initial_scene':scene.name,'initial_frame':1}
(OUT/'animation/regalia-delivery-save.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
print('REGALIA_DELIVERY_SAVED',data,flush=True)
