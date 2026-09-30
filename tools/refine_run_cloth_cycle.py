"""Bake the reviewed overlap fit of consecutive physical cloth cycles."""
import bpy,ast,numpy as np,json
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.geometry import closest_point_on_tri,barycentric_transform
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'art'/'Graduate';ANIM=OUT/'animation'
PERIOD=24;SCALE=1.75/4.8
scene=next(s for s in bpy.data.scenes if s.name.startswith('02_RUN'))
bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
stoles=[o for o in scene.objects if 'Blue and gold stole' in o.get('graduate_role','') or 'Stole woven bar' in o.get('graduate_role','')]
# Reuse only the three pure baking helpers, never run the simulation script.
tree=ast.parse((ROOT/'tools'/'simulate_graduate_cloth.py').read_text(encoding='utf-8'))
helpers=ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['fcurves','skin','bake_keys']],type_ignores=[])
exec(compile(helpers,'cloth_bake_helpers','exec'))
data=np.load(ANIM/'run_cycle_refinement.npz')
periodic=data['periodic'].copy()
old=np.load(ANIM/'run_physical_cloth.npz')
verts=[v.co.copy() for v in gown.data.shape_keys.key_blocks[0].data]
fixed=np.array([v.z>=2.65 for v in verts])
periodic[:,fixed]=old['inputs'][:,fixed]
for obj in [gown]+stoles:
    basis=[v.co.copy() for v in obj.data.shape_keys.key_blocks[0].data]
    obj.shape_key_clear()
    for v,co in zip(obj.data.vertices,basis):v.co=co
gown.data.calc_loop_triangles()
triangles=[tuple(t.vertices) for t in gown.data.loop_triangles]
anchors={}
for obj in stoles:
    obmap={}
    for v in obj.data.vertices:
        if v.co.z>3.81:continue
        best=None
        for ids in triangles:
            a,b,c=[verts[j] for j in ids]
            point=closest_point_on_tri(v.co,a,b,c);dist=(v.co-point).length_squared
            if best is None or dist<best[0]:best=(dist,ids,point)
        _,ids,point=best;a,b,c=[verts[j] for j in ids]
        bary=barycentric_transform(point,a,b,c,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
        normal=(b-a).cross(c-a).normalized()
        obmap[v.index]=(ids,bary,max(.025,abs((v.co-point).dot(normal))))
    anchors[obj]=obmap
gown_samples=[];stole_samples={o:[] for o in stoles}
rig.hide_set(False)
for i,points in enumerate(periodic/SCALE):
    scene.frame_set(i+1);bpy.context.view_layer.update();world=[Vector(v) for v in points]
    gown_samples.append([skin(gown,v).inverted_safe()@world[v.index] for v in gown.data.vertices])
    for obj in stoles:
        coords=[]
        for v in obj.data.vertices:
            if v.index not in anchors[obj]:coords.append(v.co.copy());continue
            ids,bary,gap=anchors[obj][v.index];a,b,c=[world[j] for j in ids]
            normal=(b-a).cross(c-a).normalized()
            coords.append(skin(obj,v).inverted_safe()@(a*bary.x+b*bary.y+c*bary.z+normal*gap))
        stole_samples[obj].append(coords)
bake_keys(gown,gown_samples,'Graduate_Run_PhysicalGown_SeamRefined')
for obj,samples in stole_samples.items():bake_keys(obj,samples,'Graduate_Run_Refined_'+obj.name)
rig.hide_set(True);scene.frame_set(1)
np.savez_compressed(ANIM/'run_final_cloth.npz',periodic=periodic)
bpy.context.window.scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Final.blend'))
print('RUN_CYCLE_REFINED',flush=True)
