"""Read-only review of the new breathing clip, including rendered sleeves."""
import bpy,sys,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from validate_sleeve_garment_contact import Surface,visible_surfaces,compare
scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
bpy.context.window.scene=scene
roles=['02 | Bell sleeve L','02 | Bell sleeve R','Graduate | restored arm skin','Graduate | original face, hands and trousers','01 | Pleated bachelor gown']
objects=[next(o for o in scene.objects if o.get('graduate_role')==r) for r in roles]
report={'scene':scene.name,'frames':[],'method':'Rendered transverse triangle crossings, sewn shoulder attachments excluded'}
with visible_surfaces(scene,objects,'rendered'):
    for f in range(1,121):
        scene.frame_set(f);bpy.context.view_layer.update();surfaces=[Surface(o) for o in objects]
        checks={}
        for i in range(2):
            for j in [i,2,3,4]:
                result=compare(surfaces[i],surfaces[j],i==j,1e-6)
                checks[f'{i}_{j}']={k:result[k] for k in ['crossings','maximum_intersection_segment_m']}
        report['frames'].append({'frame':f,'checks':checks})
        if f%20==0:print('IDLE_CONTACT_PROGRESS',f,flush=True)
report['total_crossings']=sum(c['crossings'] for f in report['frames'] for c in f['checks'].values())
(ROOT/'art/Graduate/animation/idle-contact-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('IDLE_CONTACT_COMPLETE',report['total_crossings'],flush=True)
scene.render.image_settings.file_format='PNG'
for frame in [1,51,91]:
    scene.frame_set(frame)
    scene.render.filepath=str(ROOT/f'art/Graduate/animation/idle_frame_{frame:03}.png')
    bpy.ops.render.render(write_still=True)
print('IDLE_REVIEW_COMPLETE',flush=True)
