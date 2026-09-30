import bpy
from mathutils import Vector
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            sp=area.spaces.active
            sp.region_3d.view_distance=3.7*area.width/max(1,area.height)
            sp.region_3d.view_location=(0,0,2.45)
            sp.region_3d.view_rotation=(Vector((7,-17,7))-Vector((0,0,2.45))).to_track_quat('Z','Y')
bpy.context.window.scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=bpy.data.filepath)
