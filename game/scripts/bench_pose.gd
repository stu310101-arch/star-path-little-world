extends RefCounted

# The rest asset is a small independent cache of the delivered Idle character.
# Its corrective lap/hem shapes cannot overwrite the walk or front-flip cloth.
const REST_MODEL: String = "res://assets/character/graduate_rest.glb"
const POSE_STEPS: int = 12
var model: Node3D
var walking_model: Node3D
var meshes: Array[MeshInstance3D] = []
var current_amount: float = 0.0

func configure(visual: Node3D, locomotion_model: Node3D) -> void:
	walking_model = locomotion_model
	model = (load(REST_MODEL) as PackedScene).instantiate() as Node3D
	model.name = "BenchRestModel"
	visual.add_child(model)
	model.visible = false
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		meshes.append(node as MeshInstance3D)

func set_amount(amount: float, _elapsed: float = 0.0) -> void:
	if model == null:
		return
	current_amount = clampf(amount, 0.0, 1.0)
	walking_model.visible = false
	model.visible = true
	var sample: float = current_amount * POSE_STEPS
	var lower: int = int(floorf(sample))
	var fraction: float = sample - lower
	for mesh: MeshInstance3D in meshes:
		for index: int in range(mesh.get_blend_shape_count()):
			var weight: float = 0.0
			if index + 1 == lower:
				weight = 1.0 - fraction
			elif index + 1 == lower + 1:
				weight = fraction
			mesh.set_blend_shape_value(index, weight)

func finish() -> void:
	if model != null:
		model.visible = false
	if walking_model != null:
		walking_model.visible = true
	current_amount = 0.0
