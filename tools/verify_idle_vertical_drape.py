"""Read-only validation limited to the new Idle lower drape and its contacts."""
from pathlib import Path
import sys,json,bpy,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import evaluated_points
from validate_sleeve_garment_contact import visible_surfaces,Surface,compare
from audit_regalia_pairs import classify_source,relation
from repair_idle_gown_hang import BODY,GOWN,lower_body_faces
from postprocess_regalia_layers import array_surface
scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'));bpy.context.window.scene=scene
roles={o.get('graduate_role'):o for o in scene.objects if o.type=='MESH' and o.get('graduate_role')}
gown=roles[GOWN];body=roles[BODY];objects=[gown,body]+[o for r,o in roles.items() if r.startswith(('02 |','03 |','04 |'))]
rest=np.asarray([v.co[:] for v in gown.data.vertices])
# The documented sewing regions are defined on the original Jump template,
# just as audit_regalia_pairs does. Idle's base mesh was inverse-skinned from
# a posed cache, so using its current coordinates would mislabel upper seams.
template_scene=next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
template_gown=next(o for o in template_scene.objects if o.get('graduate_role')==GOWN)
seams={p.index for p in template_gown.data.polygons if p.center.z>3.05 and abs(p.center.x)>.34}
body_faces=lower_body_faces(body,3.2);rows=[];loops={};first={}
lower_vertices=set(range(18*48))|set(range(1200,len(gown.data.vertices)))
with visible_surfaces(scene,objects,'rendered'):
    for frame in range(1,122):
        scene.frame_set(frame);bpy.context.view_layer.update()
        surfaces={o.get('graduate_role'):Surface(o) for o in objects}
        for obj in objects:classify_source(surfaces[obj.get('graduate_role')],obj)
        a=surfaces[GOWN];entry={'frame':frame,'lower_cuff':{},'outside_lower_area_free_contacts':{},'lower_body':{},'gown_self':compare(a,a,True,1e-6)['crossings']}
        for role,b in surfaces.items():
            if role.startswith('02 |'):
                stats=compare(a,b,False,1e-6)
                entry['lower_cuff'][role]=sum(any(v in lower_vertices for v in a.triangles[ia]) for ia,ib in stats['triangle_pairs'])
                entry['outside_lower_area_free_contacts'][role]=sum(not any(v in lower_vertices for v in a.triangles[ia]) and relation(a,ia,b,ib,seams)=='independent_surface_contact' for ia,ib in stats['triangle_pairs'])
        points=evaluated_points(body)
        for key,faces in body_faces.items():entry['lower_body'][key]=compare(a,array_surface(points,faces),False,1e-6)['crossings']
        if frame==1:first={o:evaluated_points(o) for o in objects}
        if frame==121:loops={o.get('graduate_role'):float(np.linalg.norm(evaluated_points(o)-first[o],axis=1).max()) for o in objects}
        rows.append(entry)
    scene.frame_set(1)
report={'source':bpy.data.filepath,'frames':rows,'loop_errors_m':loops,'complete':True,
        'scope':'Modified lower gown rows0-17 including front split vertices. Upper attachment contacts are retained separately and not claimed repaired.',
        'clear':all(not r['gown_self'] and not any(r['lower_cuff'].values()) and not any(r['lower_body'].values()) for r in rows)}
(ROOT/'art/Graduate/animation/idle-vertical-drape-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('IDLE_VERTICAL_VERIFY',report['clear'],max(loops.values()),flush=True)
assert report['clear']
assert max(loops.values())<2e-6
