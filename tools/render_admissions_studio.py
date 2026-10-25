"""Fast visual review of the saved editable studio, separate from generation."""
import bpy
from pathlib import Path
from mathutils import Vector

root = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(root / 'art/AdmissionsRoom/AdmissionsStudio.blend'))
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=12
scene.cycles.use_denoising=True
scene.render.resolution_x=1200
scene.render.resolution_y=750
scene.render.resolution_percentage=100
scene.render.filepath=str(root/'art/AdmissionsRoom/studio-entry.png')
bpy.ops.render.render(write_still=True)
camera=scene.camera
camera.location=Vector((-1.9,-.25,2.25))
target=Vector((-4.8,2.35,.78))
camera.rotation_euler=(target-camera.location).to_track_quat('-Z','Y').to_euler()
camera.data.lens=37
scene.render.filepath=str(root/'art/AdmissionsRoom/studio-general-detail.png')
bpy.ops.render.render(write_still=True)
