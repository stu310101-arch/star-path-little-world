"""Art-direct baked sleeve secondary motion, preserving its average drape."""
import bpy, sys, json
import numpy as np
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SCALE, SkinBinding, evaluated_points, bake_keys
from simulate_sleeve_cloth import bake_loop, contact_clearance
from sleeve_arm_colliders import arm_capsule_inputs
from cloth_surface_helpers import closed_body_topology, body_surface_positions
from validate_sleeve_garment_contact import visible_surfaces

roles=('02 | Bell sleeve L','02 | Bell sleeve R')
reports=[]
for label,prefix,gain in [('walk','01_WALK',.30),('run','02_RUN',.42),('jump','03_JUMP',.50)]:
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    sleeves=[next(o for o in scene.objects if o.get('graduate_role')==r) for r in roles]
    body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
    offsets=np.cumsum([0]+[len(o.data.vertices) for o in sleeves])
    polys=[tuple(int(i+off) for i in p.vertices) for o,off in zip(sleeves,offsets) for p in o.data.polygons]
    pins=[]
    for o in sleeves:
        group=o.vertex_groups['Sleeve shoulder seam only']
        pins.extend(next((g.weight for g in v.groups if g.group==group.index),0.) for v in o.data.vertices)
    fixed=np.asarray(pins)>.999
    bodyids,bodyfaces=closed_body_topology(body)
    with visible_surfaces(scene,[body]+sleeves,'simulation'):
        bindings=[SkinBinding(o,rig) for o in sleeves]
        local=[];original=[]
        for f in range(1,scene.frame_end+1):
            scene.frame_set(f);bpy.context.view_layer.update()
            world=[evaluated_points(o) for o in sleeves]
            original.append(np.concatenate(world))
            local.append(np.concatenate([np.asarray(b.inverse_points(p)) for b,p in zip(bindings,world)]))
        local=np.asarray(local);original=np.asarray(original)
        # Inverse-skin coordinates separate skeletal swing from fabric-only
        # flutter. Keep the average sewn drape and reduce only secondary motion.
        if label!='jump':
            equilibrium=local.mean(axis=0,keepdims=True)
        else:
            # A jump changes gravity-relative arm pose; retain its broad drape
            # transition while suppressing quick cuff flips around it.
            radius=7; kernel=np.exp(-np.arange(-radius,radius+1)**2/18);kernel/=kernel.sum()
            padded=np.pad(local,((radius,radius),(0,0),(0,0)),mode='edge')
            equilibrium=np.stack([np.sum(padded[f:f+2*radius+1]*kernel[:,None,None],axis=0) for f in range(len(local))])
        damped=equilibrium+gain*(local-equilibrium)
        damped[:,fixed]=local[:,fixed]
        for i,o in enumerate(sleeves):
            poses=damped[:,offsets[i]:offsets[i+1]]
            if label=='jump':bake_keys(o,poses,1,'Graduate_Jump_SoftSleeve_'+roles[i])
            else:bake_loop(o,poses,'Graduate_'+label.title()+'_SoftSleeve_'+roles[i])
        physical=[];clearance=[];final_local=[[] for _ in sleeves]
        for f in range(1,scene.frame_end+1):
            scene.frame_set(f);bpy.context.view_layer.update()
            points=np.concatenate([evaluated_points(o) for o in sleeves])
            contacts=[(body_surface_positions(body,bodyids,SCALE,margin=.003),bodyfaces)]
            contacts += [(d['points'],d['faces']) for d in arm_capsule_inputs(rig,SCALE).values()]
            points,info=contact_clearance(points,contacts,fixed,polys)
            physical.append(points);clearance.append(info)
            for i,b in enumerate(bindings):final_local[i].append(b.inverse_points(points[offsets[i]:offsets[i+1]]))
        for o,poses in zip(sleeves,final_local):
            name='Graduate_'+label.title()+'_DampedSleeve_'+o.get('graduate_role')
            if label=='jump':bake_keys(o,poses,1,name)
            else:bake_loop(o,poses,name)
            o['Sleeve motion']='Damped physical secondary motion; free cuff with reduced overshoot.'
        report={'clip':label,'secondary_gain':gain,'preserved_average_drape':True,
                'body_contact_probes_remaining':sum(r['remaining_inside_probes'] for r in clearance),
                'maximum_body_clearance_correction_m':max(r['max_projection_m'] for r in clearance)}
        path=ROOT/'art/Graduate/animation'/f'{label}_sleeve_damped.npz'
        np.savez_compressed(path,original=original,physical=np.asarray(physical),local_before=local,local_after=damped,pins=pins,offsets=offsets)
        reports.append(report);print('SLEEVE_DAMPED',json.dumps(report),flush=True)
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=scene;scene.frame_set(1)
(ROOT/'tools/sleeve-damping-report.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/Graduate/Male_Graduate_Sleeves_Damped.blend'))
print('SLEEVE_DAMPING_SAVED',flush=True)
