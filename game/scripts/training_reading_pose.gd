extends RefCounted

# Runtime-only arm pose. The original walk, cloth and jump resources stay intact.
var skeleton: Skeleton3D
var baseline: Array[Transform3D] = []
var target: Array[Transform3D] = []
var globals: Array[Transform3D] = []

func configure(player: PlanetPlayer) -> void:
	skeleton = player.locomotion_skeleton
	if skeleton == null:
		skeleton = player.find_skeleton(player.locomotion_model)
	if skeleton == null:
		return
	for index: int in range(skeleton.get_bone_count()):
		baseline.append(skeleton.get_bone_pose(index))
		globals.append(skeleton.get_bone_global_pose(index))
	for side: String in ["L", "R"]:
		var sign_value: float = 1.0 if side == "L" else -1.0
		var elbow: Vector3 = skeleton.to_local(player.visual.to_global(Vector3(sign_value * .28, 1.10, .14)))
		var wrist: Vector3 = skeleton.to_local(player.visual.to_global(Vector3(sign_value * .17, 1.045, .43)))
		_aim("UpperArm." + side, elbow)
		_aim("LowerArm." + side, wrist)
		var palm: int = skeleton.find_bone("Palm." + side)
		if palm >= 0:
			_aim("Palm." + side, globals[palm].origin + skeleton.global_basis.inverse() * player.visual.global_basis * Vector3(0, .025, .16))
	var head: int = skeleton.find_bone("Head")
	if head >= 0:
		_aim("Head", globals[head].origin + skeleton.global_basis.inverse() * player.visual.global_basis * Vector3(0, 1, .16))
	for index: int in range(skeleton.get_bone_count()):
		var parent_index: int = skeleton.get_bone_parent(index)
		target.append(globals[parent_index].affine_inverse() * globals[index] if parent_index >= 0 else globals[index])

func _aim(bone_name: String, point: Vector3) -> void:
	var index: int = skeleton.find_bone(bone_name)
	if index < 0:
		return
	var pivot: Vector3 = globals[index].origin
	var direction: Vector3 = point - pivot
	if direction.length_squared() < .0001:
		return
	var rotation: Basis = Basis(Quaternion(globals[index].basis.y.normalized(), direction.normalized()))
	for child: int in range(skeleton.get_bone_count()):
		var ancestor: int = child
		while ancestor >= 0 and ancestor != index:
			ancestor = skeleton.get_bone_parent(ancestor)
		if ancestor == index:
			globals[child] = Transform3D(rotation * globals[child].basis, pivot + rotation * (globals[child].origin - pivot))

func set_amount(amount: float) -> void:
	if skeleton == null:
		return
	for index: int in range(target.size()):
		skeleton.set_bone_pose(index, baseline[index].interpolate_with(target[index], clampf(amount, 0, 1)))

func finish() -> void:
	if is_instance_valid(skeleton):
		for index: int in range(baseline.size()):
			skeleton.set_bone_pose(index, baseline[index])
