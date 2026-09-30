"""Render compact jump-action review frames from the delivery file."""
import bpy, sys, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'Graduate'/'animation'/'jump_review'
OUT.mkdir(parents=True,exist_ok=True)
scene=next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
bpy.context.window.scene=scene
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=4
scene.cycles.use_denoising=True;scene.cycles.max_bounces=3
scene.render.resolution_x=432;scene.render.resolution_y=512;scene.render.resolution_percentage=100
scene.render.threads_mode='FIXED';scene.render.threads=4
frames=[1,18,27,35,40,41,48,65]
report=[]
for f in frames:
    scene.frame_set(f);bpy.context.view_layer.update()
    visible=[o.name for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and not o.hide_render]
    scene.render.filepath=str(OUT/f'frame_{f:04d}.png')
    bpy.ops.render.render(write_still=True,scene=scene.name)
    report.append({'frame':f,'visible_character_meshes':len(visible)})
    print('JUMP_REVIEW_FRAME',f,flush=True)
(OUT/'review.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
assert all(r['visible_character_meshes']==0 for r in report if r['frame']>=41)
assert all(r['visible_character_meshes']>0 for r in report if r['frame']<=40)
print('JUMP_REVIEW_COMPLETE',flush=True)
