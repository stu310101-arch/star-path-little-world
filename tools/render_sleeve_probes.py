"""Close and full-body camera renders for physically baked sleeve review."""
import bpy,sys,argparse
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--clip',default='walk');p.add_argument('--frames',default='1,10,19,28')
a=p.parse_args(sys.argv[sys.argv.index('--')+1:])
prefix={'walk':'01_WALK','run':'02_RUN','jump':'03_JUMP'}[a.clip]
scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix));bpy.context.window.scene=scene
out=ROOT/'art'/'Graduate'/'animation'/('sleeve_'+a.clip+'_review');out.mkdir(parents=True,exist_ok=True)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=6
scene.cycles.use_denoising=True;scene.cycles.max_bounces=3
scene.render.resolution_x=640;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.threads_mode='FIXED';scene.render.threads=4
camera=scene.camera
camera.data.type='ORTHO';camera.data.ortho_scale=4.25
camera.location=(7,-12,6.5);target=Vector((0,0,3.0))
camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
for frame in map(int,a.frames.split(',')):
 scene.frame_set(frame);bpy.context.view_layer.update()
 scene.render.filepath=str(out/f'frame_{frame:04d}.png')
 bpy.ops.render.render(write_still=True)
 print('SLEEVE_PROBE',a.clip,frame,flush=True)
print('SLEEVE_PROBES_DONE',flush=True)
