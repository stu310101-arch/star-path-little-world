"""Small shoulder abduction for regalia clearance; preserves the source gait."""
import bpy,math
from mathutils import Matrix,Quaternion,Vector

ARM_BONES=('UpperArm.L','UpperArm.R')

def adjust_current_arm_pose(rig,degrees=4.0):
    """Open both arms in the torso's frontal plane, without inserting keys.

    Use immediately after evaluating the idle pose and before capturing it.
    This is additive: call once after each fresh source-pose evaluation.
    """
    if not 0<=degrees<=20:raise ValueError('Regalia shoulder abduction must be between 0 and 20 degrees')
    bpy.context.view_layer.update()
    torso=rig.pose.bones['Torso']
    forward=(torso.matrix.to_3x3()@torso.bone.matrix_local.to_3x3().inverted()@Vector((0,1,0))).normalized()
    changes=[]
    for name in ARM_BONES:
        pb=rig.pose.bones[name]
        if pb.rotation_mode!='QUATERNION':raise ValueError(name+' must use quaternion rotation')
        old_head=pb.head.copy();old=pb.matrix.copy()
        # Extract the evaluated parent/rest frame. Applying a rotation about
        # the shoulder head leaves its position and source FK motion intact.
        parent_rest=old@pb.matrix_basis.inverted()
        sign=-1 if name.endswith('.L') else 1
        turn=Quaternion(forward,math.radians(degrees)*sign).to_matrix().to_4x4()
        desired=Matrix.Translation(old_head)@turn@Matrix.Translation(-old_head)@old
        basis=parent_rest.inverted()@desired
        pb.rotation_quaternion=basis.to_quaternion().normalized()
        bpy.context.view_layer.update()
        changes.append({'bone':name,'degrees':degrees,'shoulder_head_shift_model':(pb.head-old_head).length})
    return changes

def prepare_regalia_arm_clearance(scene,rig,body,period,degrees=4.0):
    """Copy the current action and add shoulder clearance over frames 1..period+1.

    Call before cloth motion capture. Other bone channels remain in the action
    copy. The original action is retained. Returns a JSON-serializable report.
    """
    if not rig.animation_data or not rig.animation_data.action:raise ValueError('An authored gait action must be assigned')
    source=rig.animation_data.action
    if source.get('regalia_arm_clearance_degrees') is not None:
        if abs(source['regalia_arm_clearance_degrees']-degrees)>1e-6:
            raise ValueError('Use the original gait action to change an existing clearance angle')
        return {'action':source.name,'degrees':degrees,'already_applied':True}
    bpy.context.window.scene=scene;rig.hide_set(False)
    samples=[]
    for frame in range(1,period+2):
        scene.frame_set(frame);bpy.context.view_layer.update()
        samples.append({name:rig.pose.bones[name].rotation_quaternion.copy() for name in ARM_BONES})
    source.use_fake_user=True
    action=source.copy();action.name=source.name+'_RegaliaArms';action.use_fake_user=True
    rig.animation_data.action=action
    if action.slots:rig.animation_data.action_slot=action.slots[0]
    previous={};max_shoulder_shift=0.;palm_shifts=[]
    for frame,quats in enumerate(samples,1):
        scene.frame_set(frame)
        for name,q in quats.items():rig.pose.bones[name].rotation_quaternion=q
        bpy.context.view_layer.update()
        old_palms={side:rig.pose.bones['Palm.'+side].head.copy() for side in ('L','R')}
        report=adjust_current_arm_pose(rig,degrees)
        max_shoulder_shift=max(max_shoulder_shift,max(r['shoulder_head_shift_model'] for r in report))
        for name in ARM_BONES:
            pb=rig.pose.bones[name]
            if name in previous and pb.rotation_quaternion.dot(previous[name])<0:pb.rotation_quaternion.negate()
            previous[name]=pb.rotation_quaternion.copy()
            pb.keyframe_insert('rotation_quaternion',frame=frame,group=name)
        palm_shifts.extend((rig.pose.bones['Palm.'+side].head-old_palms[side]).length for side in ('L','R'))
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for fc in bag.fcurves:
                    if fc.data_path in [f'pose.bones["{name}"].rotation_quaternion' for name in ARM_BONES]:
                        for key in fc.keyframe_points:key.interpolation='LINEAR'
                        if not any(m.type=='CYCLES' for m in fc.modifiers):fc.modifiers.new('CYCLES')
    action['regalia_arm_clearance_degrees']=degrees
    scene.frame_set(1);bpy.context.view_layer.update()
    return {'action':action.name,'source_action':source.name,'body':body.name,'degrees':degrees,'frames':period+1,
        'max_shoulder_head_shift_model':max_shoulder_shift,
        'palm_head_displacement_model_minmax':[min(palm_shifts),max(palm_shifts)],'already_applied':False}
