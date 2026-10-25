"""Fast, non-destructive library revision: run only in a fresh background Blender."""
from pathlib import Path
import bpy, bmesh, math, random, json, sys, struct, zlib, os, hashlib, re, ast
import numpy as np
from mathutils import Vector, Matrix
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'art/UniversityHall';OUT=ROOT/'game/assets/university_hall';TEX=OUT/'textures'
assert not bpy.data.filepath, 'Use a fresh --factory-startup process.'
bpy.ops.wm.open_mainfile(filepath=str(ART/'UniversityHall_Library.blend'))
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;RNG=random.Random(8138);FRAME=Matrix.Identity(4)
ASSETS={key:bpy.data.collections['COL_Library_'+key] for key in ['atrium','gallery','booth','theme_urban','theme_woodland','theme_hills','theme_coast','theme_arts','theme_workshop','feature_palm','feature_dairy','feature_book','feature_tea']}
M={mat.name.removeprefix('MAT_University_Library_'):mat for mat in bpy.data.materials if mat.name.startswith('MAT_University_Library_')}
manifest=json.loads((ART/'manifest.json').read_text(encoding='utf-8'));STATS=manifest['stats']
# Reuse the exact production function definitions without its destructive startup
# or full-authoring main body. The existing editable parts remain untouched.
source=ROOT/'tools/build_university_hall.py';tree=ast.parse(source.read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),str(source),'exec'))
for col in ASSETS.values():col.hide_viewport=False;col.hide_render=False
for name,w,d,exit_prefix,exit_z in [('Atrium',32,26,'Exit',11),('Gallery',30,38,'Gallery_Return',17.8)]:
    COL=ASSETS[name.lower()]
    if scene.get('floor_single_surface'):
        raise RuntimeError('Patch already applied; do not add duplicate architecture.')
    patterns=['SM_'+name+'_'+suffix for suffix in ['Foundation','Subfloor','HonedLimestone','BorderInlay','AisleInlay']]+['SM_Floor_Medallion','SM_Floor_CompassInlay']
    remove=[ob for ob in COL.objects if any(ob.name.startswith(prefix) for prefix in patterns)]
    print('REMOVE_FLOOR_STACK',name,len(remove),flush=True)
    for ob in remove:bpy.data.objects.remove(ob,do_unlink=True)
    floor(name,w,d);entrance_wall(name,w,d);reverse_portal(exit_prefix,exit_z)
    export_asset(name.lower(),COL)
scene['floor_single_surface']=True
scene['art_revision']='r3.1-library-single-surface-floor'
for image in bpy.data.images:
    if image.source=='FILE':image.pack()
for key,col in ASSETS.items():col.hide_viewport=key!='atrium';col.hide_render=key!='atrium'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'UniversityHall_Library.blend'))
layout=json.loads((OUT/'layout.json').read_text(encoding='utf-8'))
for key,depth in [('atrium',26),('gallery',38)]:
    for x in [-8,8]:layout[key]['obstacles'].append({'name':'entrance_bookcase','center':[x,1.80,depth/2-.82],'size':[7.05,3.60,.95]})
    for collider in layout[key]['obstacles']:
        if collider['name']=='archive_door' and collider['center'][2]>0:collider['center'][2]+=.56
layout['floor_geometry']='One horizontal surface per room; tile joints, inlays and compass are atlas texels. No coincident underfloor, tile, border, or medallion meshes. Only floor has import LOD removed.'
(OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
manifest['revision']='2026-10-11-r3.1-library';manifest['stats']=STATS;manifest['textures']['floor_atlas']='Two 2048px base colour atlases plus constant 256px normal/roughness maps, on two-triangle floors; all maps mipmapped.'
manifest['surface_correction']='Removed overlapping Foundation/Subfloor/tile/inlay/medallion geometry; separate no-LOD floor surface. Positive-Z end walls/bookcases complete both rooms; return-door geometry faces the interior.'
(ART/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
(ART/'validation_report.json').write_text(json.dumps({'revision':manifest['revision'],'stage':'complete','blender':bpy.app.version_string,'assets':STATS,'total_triangles':sum(v['triangles'] for v in STATS.values()),'total_bytes':sum(v['bytes'] for v in STATS.values()),'verification':'Single-surface floor and closed entrance geometry exported. Actual moving-camera Godot verification pending.'},ensure_ascii=False,indent=2),encoding='utf-8')
area('LGT_Clerestory',(0,10.7,0),(0,0,-2),3300,(.80,.88,1),11);area('LGT_FrontFill',(0,6,10),(0,2,-8),1100,(1,.79,.56),8)
camera('CAM_Library_Player',(0,3.3,9),(0,2.8,-9),24);render('library_atrium_player','atrium')
print('LIBRARY_SURFACE_PATCH_COMPLETE',flush=True)
