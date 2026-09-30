"""Bounded read-only pose/hand-collision diagnostic; no cloth simulation or save."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from regalia_arm_clearance import adjust_current_arm_pose,prepare_regalia_arm_clearance
from cloth_surface_helpers import closed_body_topology,body_surface_positions,inside
SCALE=1.75/4.8
report={'original_actions':[{'name':a.name,'frame_range':list(a.frame_range)} for a in bpy.data.actions if a.name.startswith('Man_')]}
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'));bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE');rig.hide_set(False)
body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
gait_action=rig.animation_data.action
body_groups=[{body.vertex_groups[g.group].name:g.weight for g in v.groups} for v in body.data.vertices]
contact_ids=[77,117,119,122,124,71,333,331,332,379,387,377,383,381]
report['contact_source_vertices']=[{'id':i,'rest_position':list(body.data.vertices[i].co),'groups':body_groups[i]} for i in contact_ids]
body_ids,body_faces=closed_body_topology(body)
report['collider_vertices']=len(body_ids);report['collider_faces']=len(body_faces)
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
rig.animation_data.action=bpy.data.actions['Man_Idle']
if rig.animation_data.action.slots:rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(17);bpy.context.view_layer.update()
base_pose={b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}
old=[v.co.copy() for v in gown.data.vertices]
for co in old:co.z+=.52*min(1,max(0,(2.65-co.z)/(2.65-.62)))
cuts=[1,4,6,4,3,2,2,2];cloth=[]
for row,count in enumerate(cuts):
    for step in range(count):
        for j in range(48):
            co=old[row*48+j].lerp(old[(row+1)*48+j],step/count)
            if co.z<2.65:cloth.append(co)
def skin_co(co):
    if co.z<2.22:w={'Hips':1.}
    else:
        t=min(1,max(0,(co.z-2.20)/.55));w={'Hips':1-t,'Abdomen':t}
    result=Vector()
    for name,weight in w.items():
        pb=rig.pose.bones[name];result+=(pb.matrix@pb.bone.matrix_local.inverted()@co)*weight
    return result*SCALE
angles=[]
for angle in (0,4,7,10,13):
    for name,(loc,q,scale) in base_pose.items():
        pb=rig.pose.bones[name];pb.location=loc;pb.rotation_quaternion=q;pb.scale=scale
    bpy.context.view_layer.update();changes=adjust_current_arm_pose(rig,angle)
    points=body_surface_positions(body,body_ids,SCALE,margin=.004)
    tree=BVHTree.FromPolygons(points,body_faces,all_triangles=True)
    contacts=[]
    for vi,co in enumerate(cloth):
        p=skin_co(co);near,normal,fi,dist=tree.find_nearest(p)
        if near is None or (p-near).dot(normal)>=0 or not inside(tree,p):continue
        sid=[body_ids[i] for i in body_faces[fi]];weights={}
        for i in sid:
            for name,w in body_groups[i].items():weights[name]=weights.get(name,0)+w
        region=max(weights,key=weights.get) if weights else ''
        contacts.append({'vertex':vi,'co_m':list(p),'depth_mm':dist*1000,'region':region,'source_ids':sid})
    palms={side:list((rig.matrix_world@rig.pose.bones['Palm.'+side].head)*SCALE) for side in ('L','R')}
    angles.append({'degrees':angle,'inside_count':len(contacts),'maximum_depth_mm':max((r['depth_mm'] for r in contacts),default=0),
        'by_region':{region:sum(c['region']==region for c in contacts) for region in sorted(set(c['region'] for c in contacts))},
        'worst':sorted(contacts,key=lambda r:r['depth_mm'],reverse=True)[:10],'palms_m':palms,'pose_changes':changes})
report['idle_angle_tests']=angles
rig.animation_data.action=gait_action
if gait_action.slots:rig.animation_data.action_slot=gait_action.slots[0]
report['gait_adjustments']=[]
for gait_scene in [s for s in bpy.data.scenes if s.name.startswith(('01_WALK','02_RUN'))]:
    bpy.context.window.scene=gait_scene
    gait_rig=next(o for o in gait_scene.objects if o.type=='ARMATURE')
    gait_body=next(o for o in gait_scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
    period=36 if 'WALK' in gait_scene.name else 24
    adjusted=prepare_regalia_arm_clearance(gait_scene,gait_rig,gait_body,period,degrees=7)
    endpoint=[]
    for f in (1,period+1):
        gait_scene.frame_set(f);bpy.context.view_layer.update()
        endpoint.append({name:list(gait_rig.pose.bones[name].rotation_quaternion) for name in ('UpperArm.L','UpperArm.R')})
    adjusted['endpoint_quaternion_max_gap']=max(abs(endpoint[0][name][i]-endpoint[1][name][i]) for name in endpoint[0] for i in range(4))
    report['gait_adjustments'].append(adjusted)
out=ROOT/'tools/regalia-hand-start-diagnosis.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('REGALIA_HAND_DIAGNOSIS',json.dumps(report),flush=True)
