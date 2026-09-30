"""Promote reviewed sleeve caches and make the edited sleeves easy to inspect."""
import bpy
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=scene;scene.frame_set(1)
for obj in scene.objects:obj.select_set(False)
sleeve=next(o for o in scene.objects if o.get('graduate_role')=='02 | Bell sleeve L')
sleeve.select_set(True);bpy.context.view_layer.objects.active=sleeve
for screen in bpy.data.screens:
 for area in screen.areas:
  if area.type=='VIEW_3D':
   sp=area.spaces.active;sp.shading.type='SOLID';sp.shading.color_type='MATERIAL'
   sp.region_3d.view_location=(0,0,2.6);sp.region_3d.view_distance=6.5
   sp.region_3d.view_perspective='PERSP'
   sp.region_3d.view_rotation=Vector((5,-12,4)).to_track_quat('Z','Y')
text=bpy.data.texts.get('SLEEVE PHYSICS - Readme') or bpy.data.texts.new('SLEEVE PHYSICS - Readme')
text.clear();text.write('''袖子布料動畫\n\n左右袖子從肩部至袖口整段修窄，保留手肘活動空間。\n連續截面避免逐頂點平均造成塌縮；重力與帶阻尼的慣性驅動\n袖口的延遲回擺、傾斜和輕微截面形變，並維持袖口周長。\n這是美術控制的簡化布料次級動作，烘焙為 Walk、Run、JumpDown\n形狀鍵，並非此版袖子直接使用完整 Cloth 求解器。\n\n原有下袍 Cloth 烘焙與骨架動作保留。學士袍以黑色為主，衣長在膝下至小腿之間。\n跳下動作搭配閃光與粒子消失，不包含傳送門或虛空場景。\n\nBlender：頂部場景選單切換 01_WALK／02_RUN／03_JUMP，空白鍵播放／暫停。\nGodot：開啟 Godot/project.godot，按 F5 執行。\n1 走路、2 跑步、3 跳下消失、R 重播；空白處按住左鍵拖曳旋轉，\n滾輪縮放，Home 重設視角。GLB 位於 Godot/assets/graduate.glb。\n\n遊戲端直接播放布料烘焙，不需即時運算 Cloth。新增動作時需重新處理衣物。\n''')
text.write('\n袖口的額外甩動已收斂，保留平均垂墜形狀與柔軟回擺；不是未調整的模擬原始結果。\n袖內補回原角色的手臂皮膚、材質和骨架權重。\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/Graduate/Male_Graduate_GameReady.blend'))
print('SLEEVE_DELIVERY_SAVED',flush=True)
