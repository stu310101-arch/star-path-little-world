extends Node3D
## The cabinet exhibit is independent of the playable avatar and door hinges.
const MODEL: String = "res://assets/exhibits/furina/furina_splendor.glb"
var state: String = "waiting"
var error: String = ""
var figure: Node3D
var packed: PackedScene

func _ready() -> void:
	name = "FurinaDisplay"
	rotation.y = -PI / 2.0
	# The socket is 3 mm below the top of its velvet pad.
	position.y = .004
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("request_resource", MODEL, 210)

func _process(_delta: float) -> void:
	if state in ["ready", "error"]:
		return
	if state == "waiting":
		var packs: Node = get_node_or_null("/root/WebPacks")
		if packs != null:
			error = str(packs.call("resource_error", MODEL))
			if not error.is_empty():
				_fail(error)
				return
			if not bool(packs.call("is_resource_ready", MODEL)):
				return
		packed = load(MODEL) as PackedScene
		if packed == null:
			_fail("無法載入芙寧娜展示模型")
			return
		state = "instantiating"
		return
	figure = packed.instantiate() as Node3D
	packed = null
	if figure == null:
		_fail("無法建立芙寧娜展示模型")
		return
	figure.name = "FurinaWithSplendor"
	add_child(figure)
	# Texture cutouts must write depth behind the cabinet glass. Blended hair
	# and face overlays otherwise sort over one another in Compatibility mode.
	for child: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			if material == null:
				continue
			material = material.duplicate() as StandardMaterial3D
			material.cull_mode = BaseMaterial3D.CULL_DISABLED
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				material.alpha_scissor_threshold = .35
			mesh.set_surface_override_material(surface, material)
	var light: OmniLight3D = OmniLight3D.new()
	light.name = "ExhibitFill"
	light.position = Vector3(-.25, 1.15, .65)
	light.light_color = Color("e2efff")
	light.light_energy = .55
	light.omni_range = 1.7
	light.shadow_enabled = false
	add_child(light)
	state = "ready"
	set_process(false)

func _fail(message: String) -> void:
	error = message
	state = "error"
	push_error(message)

func retry() -> void:
	if state != "error":
		return
	error = ""
	state = "waiting"
	set_process(true)
