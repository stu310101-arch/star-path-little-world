"""Reopen and verify the actual saved training-room asset, then render views."""
from pathlib import Path
import bpy, bmesh, json, sys, math
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'TrainingRoom'
s=bpy.context.scene
assert Path(bpy.data.filepath).resolve()==(OUT/'WordKing_TrainingRoom.blend').resolve()
assert sum(o.get('device_type')=='wordking_training' for o in s.objects)==1
assert sum(bool(o.get('intentionally_empty')) for o in s.objects)==6
assert len([o for o in s.objects if o.type=='ARMATURE'])==0
assert len([o for o in s.objects if o.get('gaming_station_index')])==3
assert sum(bool(o.get('upholstered')) for o in s.objects)>=20
assert s.render.engine=='CYCLES'
assert s.render.compositor_device=='CPU'
assert list(s['room_dimensions_m'])==[20,18,3.4]
assert all(math.isfinite(x) for o in s.objects for x in o.location)
upholstery=[]
for obj in s.objects:
    if obj.name.startswith('LOUNGE') and obj.get('upholstered'):
        bm=bmesh.new();bm.from_mesh(obj.data)
        nonmanifold=sum(not e.is_manifold for e in bm.edges)
        assert nonmanifold==0, (obj.name,nonmanifold)
        upholstery.append({'object':obj.name,'vertices':len(bm.verts),'closed_surface':True})
        bm.free()
(OUT/'validation'/'upholstery_validation.json').write_text(json.dumps({'mesh_count':len(upholstery),'closed_upholstery_surfaces':upholstery,'source':bpy.data.filepath},indent=2),encoding='utf8')
print('REOPEN_VALIDATED: one training device, six empty sockets, three chairs, no characters; CPU compositor',flush=True)
s.render.resolution_percentage=100
s.cycles.use_denoising=True;s.cycles.denoiser='OPENIMAGEDENOISE'
s.cycles.denoising_use_gpu=False
s.render.use_persistent_data=False
quick='--quick' in sys.argv
shots=[('CAM | 05 upholstered leather sofa','05_sofa_check.png',960,720,24),('CAM | 01 reference overview','01_spacious_check.png',800,600,12)] if quick else [
 ('CAM | 01 reference overview','01_overview.png',1152,864,24),
 ('CAM | 05 upholstered leather sofa','05_leather_sofa.png',1080,810,32),
 ('CAM | 02 eye-level room','02_interior.png',1040,700,20),
 ('CAM | 03 WordKing device','03_wordking_device.png',1000,800,24),
 ('CAM | 04 empty display','04_empty_display.png',960,720,16),
]
if '--interior-only' in sys.argv:
    shots=[('CAM | 02 eye-level room','02_interior.png',1040,700,20)]
    previous=json.loads((OUT/'validation'/'render_validation.json').read_text(encoding='utf8'))
    done=[v for v in previous['completed_views'] if v['file']!='02_interior.png']
else:done=[]
for cam,file,w,h,samples in shots:
    enclosed=bpy.data.collections['13 | Roof and front wall - toggle for enclosed room']
    enclosed.hide_render=not cam.startswith('CAM | 02')
    enclosed.hide_viewport=enclosed.hide_render
    s.camera=bpy.data.objects[cam]
    s.render.resolution_x=w;s.render.resolution_y=h;s.cycles.samples=samples
    s.render.filepath=str(OUT/'previews'/file)
    print('RENDER_BEGIN',file,flush=True)
    bpy.ops.render.render(write_still=True)
    done.append({'camera':cam,'file':file,'resolution':[w,h],'samples':samples})
    print('RENDER_COMPLETE',file,flush=True)
    (OUT/'validation'/('quick_render.json' if quick else 'render_validation.json')).write_text(json.dumps({'source':bpy.data.filepath,'reopened_and_validated':True,'completed_views':done},indent=2),encoding='utf8')
