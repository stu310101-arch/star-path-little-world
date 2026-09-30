"""Narrow sleeve cross-sections consistently across all baked clips."""
import bpy,sys,json
import numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SCALE,SkinBinding,evaluated_points,bake_keys
from simulate_sleeve_cloth import bake_loop,contact_clearance
from cloth_surface_helpers import closed_body_topology,body_surface_positions
from sleeve_arm_colliders import arm_capsule_inputs
from validate_sleeve_garment_contact import visible_surfaces
ROLES=('02 | Bell sleeve L','02 | Bell sleeve R')
reports=[]
# Narrow the entire sleeve, including shoulder, upper arm and elbow, by 28%.
# Longitudinal centers and the already damped secondary motion are retained.
factors=np.full(17,.72)
for label,prefix in [('walk','01_WALK'),('run','02_RUN'),('jump','03_JUMP')]:
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    sleeves=[next(o for o in scene.objects if o.get('graduate_role')==role) for role in ROLES]
    body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
    for o in sleeves:
        if o.get('Sleeve cuff width factor'):raise RuntimeError('Sleeve already narrowed: '+o.name)
        if len(o.data.vertices)!=545:raise RuntimeError('Unexpected topology')
        for key in o.data.shape_keys.key_blocks:
            points=np.asarray([v.co[:] for v in key.data])
            for row,factor in enumerate(factors):
                section=points[row*32:(row+1)*32]
                center=section.mean(axis=0)
                points[row*32:(row+1)*32]=center+(section-center)*factor
            key.data.foreach_set('co',points.reshape(-1))
        for v,k in zip(o.data.vertices,o.data.shape_keys.key_blocks[0].data):v.co=k.co
        o['Sleeve cuff width factor']=.72
        o['Sleeve tailoring']='Entire sleeve cross-section narrowed 28%, from shoulder through elbow to cuff.'
        o.data.update()
    offsets=np.cumsum([0]+[len(o.data.vertices) for o in sleeves])
    faces=[tuple(int(i+off) for i in p.vertices) for o,off in zip(sleeves,offsets) for p in o.data.polygons]
    pins=[]
    for o in sleeves:
        group=o.vertex_groups['Sleeve shoulder seam only']
        pins.extend(next((g.weight for g in v.groups if g.group==group.index),0.) for v in o.data.vertices)
    fixed=np.asarray(pins)>.999
    bodyids,bodyfaces=closed_body_topology(body)
    with visible_surfaces(scene,[body]+sleeves,'simulation'):
        bindings=[SkinBinding(o,rig) for o in sleeves]
        poses=[[] for _ in sleeves];checks=[]
        for f in range(1,scene.frame_end+1):
            scene.frame_set(f);bpy.context.view_layer.update()
            points=np.concatenate([evaluated_points(o) for o in sleeves])
            contacts=[(body_surface_positions(body,bodyids,SCALE,margin=.003),bodyfaces)]
            contacts += [(d['points'],d['faces']) for d in arm_capsule_inputs(rig,SCALE).values()]
            points,check=contact_clearance(points,contacts,fixed,faces)
            checks.append(check)
            for i,b in enumerate(bindings):poses[i].append(b.inverse_points(points[offsets[i]:offsets[i+1]]))
        for o,data in zip(sleeves,poses):
            name='Graduate_'+label.title()+'_Tailored_'+o.get('graduate_role')
            if label=='jump':bake_keys(o,data,1,name)
            else:bake_loop(o,data,name)
        report={'clip':label,'cuff_width_factor':.72,'shoulder_width_factor':.72,
                'remaining_body_probes':sum(c['remaining_inside_probes'] for c in checks),
                'maximum_contact_adjustment_m':max(c['max_projection_m'] for c in checks)}
        reports.append(report);print('SLEEVE_TAILORED',json.dumps(report),flush=True)
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=scene;scene.frame_set(1)
(ROOT/'tools/sleeve-tailoring-report.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/Graduate/Male_Graduate_Sleeves_Tailored.blend'))
print('SLEEVE_TAILORING_SAVED',flush=True)
