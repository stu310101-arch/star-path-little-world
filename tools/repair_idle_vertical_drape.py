"""Idle-only straight gravity drape, replacing the inherited flared neutral pose.

Retains the body motion, timing, upper gown, sleeves and other clips. Creates
a new review file; no master, Godot export or other asset is replaced.
"""
from pathlib import Path
import argparse,sys,json,math,time
import bpy,numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SkinBinding,evaluated_points
from repair_graduate_regalia import triangles,bar_points
from repair_idle_gown_hang import BODY,GOWN,body_yaw,rotation_2d,lower_body_faces,clear_hanging_stole
from repair_idle_pants_clearance import topology_placket_pairs,grow_relief,points_with_relief
from repair_motion_pants_clearance import bake_isolated_cache,_protected_snapshot
from postprocess_regalia_layers import array_surface,compact_crossings
from validate_sleeve_garment_contact import visible_surfaces,Surface,compare

def smooth(t):
    t=np.clip(t,0,1);return t*t*(3-2*t)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--radius-x',type=float,default=.200)
    parser.add_argument('--front',type=float,default=.178)
    parser.add_argument('--back',type=float,default=.153)
    parser.add_argument('--probe',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    out=args.output.resolve();assert out!=Path(bpy.data.filepath).resolve()
    started=time.perf_counter();scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
    bpy.context.window.scene=scene
    roles={o.get('graduate_role'):o for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and not o.get('preview_fx')}
    gown,body=roles[GOWN],roles[BODY];rig=next(o for o in scene.objects if o.type=='ARMATURE')
    front={r:o for r,o in roles.items() if r.startswith('03 |') and r.endswith((' L',' R'))}
    bars={r:o for r,o in roles.items() if r.startswith('04 |')}
    objects=[gown,*front.values(),*bars.values()]
    protected=_protected_snapshot(objects)
    bindings={o:SkinBinding(o,rig) for o in objects};faces=triangles(gown)
    topology={o:triangles(o) for o in front.values()}
    rest=np.asarray([v.co[:] for v in gown.data.vertices]);grid=len(rest)//48*48
    pairs,unresolved=topology_placket_pairs(gown.data);assert not unresolved
    row_z=np.asarray([np.mean(rest[row*48:(row+1)*48,2]) for row in range(grid//48)])
    vertex_z=np.repeat(row_z,48)
    duplicate_to_row={b:a//48 for a,b in pairs}
    vertex_z=np.concatenate([vertex_z,[row_z[duplicate_to_row[i]] for i in range(grid,len(rest))]])
    weight=smooth((3.12-vertex_z)/(3.12-2.65))
    waist_ids=np.arange(17*48,18*48)
    skin_faces=lower_body_faces(body,3.2)
    rows=[];report={'source':bpy.data.filepath,'output':str(out),'complete':False,'saved':False,
       'scope':'Idle lower gown and attached lower front stole/bars only',
       'design':{'half_width_m':args.radius_x,'front_radius_m':args.front,'back_radius_m':args.back,'front_slit_m':.020,'vertical_pleat_m':.003,'sway_m':.0005},'frames':[]}
    report_path=out.with_suffix('.vertical-drape.json')
    def checkpoint():report_path.write_text(json.dumps(report,indent=2),encoding='utf-8')
    with visible_surfaces(scene,[body,*objects],'rendered'):
        for frame in range(1,121):
            scene.frame_set(frame);bpy.context.view_layer.update()
            posed={o:evaluated_points(o) for o in objects};bp=evaluated_points(body)
            rows.append({'frame':frame,'posed':posed,'waist':np.mean(posed[gown][waist_ids],axis=0),'yaw':body_yaw(rig),
               'pants':array_surface(bp,skin_faces['pants_legs']),
               'skin':array_surface(bp,skin_faces['skin'])})
        original=rows[0]['posed'][gown];waist0=rows[0]['waist'];yaw0=rows[0]['yaw']
        # The old cached lower form is deliberately not used as the neutral
        # silhouette. Each angular column follows a vertical fabric fold.
        center=np.array((waist0[0],-.008))
        neutral=original.copy();ring_heights=[]
        for row in range(grid//48):
            z=float(np.mean(original[row*48:(row+1)*48,2]));ring_heights.append(z)
            for col in range(48):
                angle=math.tau*col/48;crease=.003*math.cos(12*angle)
                neutral[row*48+col]=[center[0]+(args.radius_x+crease)*math.cos(angle),
                    center[1]+((args.back if math.sin(angle)>0 else args.front)+crease)*math.sin(angle),z]
        for a,b in pairs:
            neutral[a,0]=center[0]-.010;neutral[b]=neutral[a];neutral[b,0]=center[0]+.010
        # Preserve source upper waist and chest. Width below the hip is a
        # constant hanging envelope instead of an outward-opening cone.
        neutral=original+weight[:,None]*(neutral-original)
        waists=np.asarray([r['waist'] for r in rows]);lag=.85*waists+.15*np.roll(waists,3,axis=0)
        for i,row in enumerate(rows):
            angle=row['yaw']-yaw0;desired=neutral.copy()
            desired[:,:2]=(desired[:,:2]-waist0[:2])@rotation_2d(angle).T+waist0[:2]
            desired+=lag[i]-lag[0]
            desired[:,0]+=weight*.0005*(math.sin(math.tau*i/120-.35)-math.sin(-.35))
            # Apply one blend, retaining the newly canonical form already
            # blended in neutral while leaving the upper source pose exact.
            base=row['posed'][gown]
            reference=original.copy();reference[:,:2]=(reference[:,:2]-waist0[:2])@rotation_2d(angle).T+waist0[:2]
            reference+=lag[i]-lag[0]
            row['gown']=base+weight[:,None]*(reference-base)+(desired-reference)
            dirs=row['gown'].copy();dirs[:,2]=0;dirs[:,:2]-=(center+(lag[i]-lag[0])[:2])
            dirs/=np.maximum(np.linalg.norm(dirs,axis=1)[:,None],1e-12)
            row['directions']=dirs
        envelope=np.zeros(len(rest));movable=weight>.15
        for iteration in range(12):
            previous=envelope.copy()
            for row in rows:
                envelope,_,_=grow_relief(row,faces,envelope,movable,.003,.025)
            if np.max(abs(envelope-previous))<1e-8:break
        report['constant_body_relief']={'vertices':np.flatnonzero(envelope>0).tolist(),'max_m':float(envelope.max()),'passes':iteration+1}
        samples={o:[] for o in objects};maximum_free=0
        for i,row in enumerate(rows):
            scene.frame_set(row['frame']);bpy.context.view_layer.update()
            fixed=points_with_relief(row,envelope);surface=array_surface(fixed,faces)
            contacts={name:compact_crossings(surface,target) for name,target in [('pants',row['pants']),('skin',row['skin']),('self',surface)] if name!='self'}
            contacts['self']=compact_crossings(surface,surface,True)
            posed={gown:fixed};accessories={}
            for role,obj in front.items():
                old=row['posed'][obj];p=old.copy();old0=rows[0]['posed'][obj]
                side=1 if old0[5*4+3,0]>old0[5*4,0] else -1
                anchor=np.mean(old0[20:24],axis=0)
                row_weights=np.zeros(11)
                for r in range(6,11):
                    ids=slice(4*r,min(4*r+4,len(p)));z=float(np.mean(old0[ids,2]))
                    amount=float(smooth((1.16-z)/.19));row_weights[r]=amount
                    z+=float((lag[i]-lag[0])[2])
                    width=float(np.linalg.norm(old0[r*4+3]-old0[r*4])) if r<10 else 0.
                    if r<10:width=min(width,.070)
                    values=[-.5,-.43,.43,.5] if r<10 else [0.]
                    desired=[]
                    for fraction in values:
                        x=anchor[0]+side*fraction*width
                        y=center[1]-args.front*math.sqrt(max(.05,1-((x-center[0])/args.radius_x)**2))-.009
                        point=np.array((x,y,z));point[:2]=(point[:2]-waist0[:2])@rotation_2d(row['yaw']-yaw0).T+waist0[:2]+(lag[i]-lag[0])[:2]
                        desired.append(point)
                    p[ids]+=amount*(np.asarray(desired)-p[ids])
                posed[obj],_=clear_hanging_stole(p,topology[obj],fixed,faces,row_weights)
                lower_faces=[f for f in topology[obj] if any(v//4>=6 for v in f)]
                accessories[role]=compact_crossings(array_surface(posed[obj],lower_faces),surface)
            torso=rig.pose.bones['Torso'];forward=rig.matrix_world.to_3x3()@torso.matrix.to_3x3()@torso.bone.matrix_local.to_3x3().inverted()@Vector((0,-1,0))
            for role,obj in bars.items():
                parent=next(o for r,o in front.items() if r.endswith(' '+role.rsplit(' ',1)[1][0]))
                posed[obj]=bar_points(posed[parent],int(role[-1]),np.asarray(forward.normalized()))
            entry={'frame':row['frame'],'contacts':contacts,'lower_stoles':accessories,
                'lower_width_m':float(np.ptp(fixed[:48,0])),'front_slit_m':float(np.linalg.norm(fixed[pairs[0][0]]-fixed[pairs[0][1]])),
                'upper_change_m':float(np.linalg.norm(fixed[weight==0]-row['posed'][gown][weight==0],axis=1).max(initial=0))}
            report['frames'].append(entry)
            assert entry['upper_change_m']<1e-10,'Upper breathing geometry must remain unchanged'
            maximum_free=max(maximum_free,max(v['crossings'] for v in [*contacts.values(),*accessories.values()]))
            for obj in objects:samples[obj].append(np.asarray(bindings[obj].inverse_points(posed[obj])))
            if (i+1)%20==0:print('VERTICAL_DRAPE_FRAME',i+1,contacts,flush=True);checkpoint()
        report['maximum_checked_crossings']=maximum_free
        if maximum_free:checkpoint();raise AssertionError('New Idle drape retains lower body/self/stole crossings; inspect report')
        if not args.probe:
            for obj in objects:
                obj.data=obj.data.copy();bake_isolated_cache(obj,samples[obj],'Idle vertical drape | '+obj.get('graduate_role'),loop=True)
    assert protected==_protected_snapshot(objects),'Protected body, sleeves, other clips, rig or timing changed'
    report['protected_data_preserved']=True
    if not args.probe:
        bpy.context.window.scene=scene;scene.frame_set(1);bpy.context.view_layer.update()
        scene.sync_mode='AUDIO_SYNC'
        for screen in bpy.data.screens:
            for area in screen.areas:
                if area.type=='VIEW_3D':
                    area.spaces.active.overlay.show_overlays=False
                    area.spaces.active.region_3d.view_perspective='CAMERA'
        bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(out));report['saved']=True
    report['complete']=True;report['seconds']=time.perf_counter()-started;checkpoint()
    print('VERTICAL_DRAPE_DONE',report['saved'],report['seconds'],flush=True)

if __name__=='__main__':main()
