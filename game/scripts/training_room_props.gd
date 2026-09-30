extends Node3D

# Room furniture actions share the seating/book router's nearest-target rules.
# The controls below operate the imported authored parts, never a second model.
const STARRY_NIGHT: String = "res://assets/training_room/textures/starry_night.jpg"
var room: Node3D
var model: Node3D
var router: Node
var targets: Dictionary = {}
var door_pivots: Array[Node3D] = []
var door_angles: Array[float] = []
var door_tween: Tween
var cabinet_open: bool = false
var projector_on: bool = true
var lamp_on: bool = true
var screens: Dictionary = {}
var computer_positions: Dictionary = {}
var lamp_meshes: Array[Node3D] = []
var lamp_light: OmniLight3D
var preview: SubViewport
var preview_turntable: Node3D

func configure(host: Node3D, art: Node3D, interactions: Node, layout: Dictionary) -> void:
	room = host
	model = art
	router = interactions
	name = "FurnitureActions"
	router.connect("custom_action", _activate)
	_register("projector", "開關單字王投影", _vec(layout.get("device", [.65,.034,-.8]) as Array), 1.85, "projector")
	for row: Dictionary in layout.get("computers", []):
		var id: String = str(row.get("id", "computer_%d" % screens.size()))
		var node: Node3D = _part(str(row.get("node_name", "")))
		if node == null:
			continue
		screens[id] = node
		computer_positions[id] = _vec(row.get("position", row.get("approach", [0,0,0])) as Array)
		_register(id, "開關電腦螢幕", _vec(row.get("approach", row.get("position", [0,0,0])) as Array), 1.25, "computer", row)
	_build_doors(layout.get("cabinet_doors", []) as Array)
	for row: Dictionary in layout.get("decor_targets", []):
		var id: String = str(row.get("id", "decor_%d" % targets.size()))
		var kind: String = str(row.get("kind", "decoration"))
		var point: Vector3 = _vec(row.get("approach", row.get("position", [0,0,0])) as Array)
		var prompt_text: String = "端詳「%s」" % str(row.get("label", "擺飾"))
		if kind == "painting":
			prompt_text = "欣賞梵谷《星夜》"
		elif kind == "lamp":
			prompt_text = "開關閱讀燈"
		_register(id, prompt_text, point, float(row.get("radius", 1.65)), kind, row)
		if kind == "lamp":
			var lamp_part: Node3D = _part(str(row.get("node_name", "")))
			if lamp_part != null:
				lamp_meshes.append(lamp_part)
			lamp_light = OmniLight3D.new()
			lamp_light.name = "ReadingFloorLight"
			lamp_light.position = _vec(row.get("light_position", row.get("position", [0,1.5,0])) as Array)
			lamp_light.light_color = Color("ffddb0")
			lamp_light.light_energy = .24
			lamp_light.omni_range = 3.2
			lamp_light.shadow_enabled = false
			add_child(lamp_light)

func _vec(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _part(part_name: String) -> Node3D:
	if part_name.is_empty():
		return null
	return model.find_child(part_name, true, false) as Node3D

func _register(id: String, label: String, point: Vector3, radius: float, kind: String, details: Dictionary = {}) -> void:
	targets[id] = {"kind":kind,"details":details}
	point.y = float((room.get("layout") as Dictionary).get("floor_y", .0375)) + .035
	router.call("register_target", {"id":id,"kind":"custom","label":label,"position":point,"radius":radius,"collider_name":details.get("collider_name", "__none")})

func _build_doors(rows: Array) -> void:
	for row: Dictionary in rows:
		var door: Node3D = _part(str(row.get("node_name", "")))
		if door == null:
			continue
		var pivot: Node3D = Node3D.new()
		pivot.name = "CabinetHinge_%02d" % door_pivots.size()
		pivot.position = _vec(row.get("hinge", [0,0,0]) as Array)
		add_child(pivot)
		door.reparent(pivot, true)
		door_pivots.append(pivot)
		door_angles.append(float(row.get("open_angle", deg_to_rad(-85.0))))
		# Both tiers open together; every bay offers the same cabinet action.
		_register("cabinet_%02d" % door_pivots.size(), "開關展示櫃門", _vec(row.get("approach", [6,.04,-3.6]) as Array), 1.55, "cabinet", row)

func use_nearest_computer() -> bool:
	var player: Node3D = room.get("player") as Node3D
	var best_id: String = ""
	var distance: float = 2.4
	for id: String in computer_positions:
		var at: Vector3 = computer_positions[id] as Vector3
		var candidate: float = Vector2(player.position.x-at.x,player.position.z-at.z).length()
		if candidate < distance:
			distance = candidate
			best_id = id
	if best_id.is_empty():
		return false
	_activate(best_id)
	return true

func _activate(id: String) -> void:
	if not targets.has(id):
		return
	var row: Dictionary = targets[id] as Dictionary
	var details: Dictionary = row.details as Dictionary
	match str(row.kind):
		"projector":
			projector_on = not projector_on
			for part: Node in model.find_children("SM_Device_Hologram*", "MeshInstance3D", true, false):
				(part as Node3D).visible = projector_on
			var effect: Node3D = room.get_node_or_null("WordKingProjection") as Node3D
			if effect != null:
				effect.visible = projector_on
		"computer":
			var monitor: Node3D = screens.get(id) as Node3D
			if monitor != null:
				monitor.visible = not monitor.visible
		"cabinet":
			if door_tween != null and door_tween.is_running():
				return
			cabinet_open = not cabinet_open
			door_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			for index: int in range(door_pivots.size()):
				door_tween.tween_property(door_pivots[index], "rotation:y", door_angles[index] if cabinet_open else 0.0, .7)
		"lamp":
			lamp_on = not lamp_on
			if lamp_light != null:
				lamp_light.visible = lamp_on
			for lamp: Node3D in lamp_meshes:
				for descendant: Node in _mesh_nodes(lamp):
					var mesh: MeshInstance3D = descendant as MeshInstance3D
					for surface: int in range(mesh.mesh.get_surface_count()):
						var original: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
						if original != null and original.emission_enabled:
							var material: StandardMaterial3D = original.duplicate() as StandardMaterial3D
							material.emission_enabled = lamp_on
							mesh.set_surface_override_material(surface, material)
		"painting":
			router.call("show_inspection", "梵谷《星夜》", "Vincent van Gogh · 1889", load(STARRY_NIGHT) as Texture2D)
		_:
			var source: Node3D = _part(str(details.get("node_name", "")))
			var texture: Texture2D = _make_preview(source) if source != null else null
			router.call("show_inspection", str(details.get("label", "擺飾")), "左右方向鍵旋轉查看 · Esc 放回", texture)

func _mesh_nodes(parent: Node3D) -> Array[Node]:
	var result: Array[Node] = parent.find_children("*", "MeshInstance3D", true, false)
	if parent is MeshInstance3D:
		result.append(parent)
	return result

func _make_preview(source: Node3D) -> Texture2D:
	_clear_preview()
	preview = SubViewport.new()
	preview.name = "ObjectInspection"
	preview.size = Vector2i(512,512)
	preview.own_world_3d = true
	preview.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(preview)
	var background: WorldEnvironment = WorldEnvironment.new()
	background.environment = Environment.new()
	background.environment.background_mode = Environment.BG_COLOR
	background.environment.background_color = Color("28464a")
	background.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	background.environment.ambient_light_color = Color("d7e5e0")
	background.environment.ambient_light_energy = .8
	preview.add_child(background)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40,-30,0)
	key.light_energy = 1.0
	preview.add_child(key)
	var bounds: AABB = AABB()
	var started: bool = false
	for part: Node in _mesh_nodes(source):
		var mesh: MeshInstance3D = part as MeshInstance3D
		var transformed: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(transformed) if started else transformed
		started = true
	preview_turntable = Node3D.new()
	preview.add_child(preview_turntable)
	var assembly: Node3D = Node3D.new()
	preview_turntable.add_child(assembly)
	var preview_model: Node3D = source.duplicate(0) as Node3D
	assembly.add_child(preview_model)
	preview_model.transform = source.global_transform
	assembly.position = -bounds.get_center()
	preview_turntable.scale = Vector3.ONE * (1.65 / maxf(bounds.size.length(), .01))
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0,.35,2.8)
	camera.fov = 42
	preview.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	return preview.get_texture()

func _process(delta: float) -> void:
	if preview == null:
		return
	if not bool(router.call("is_busy")):
		_clear_preview()
		return
	var spin: float = Input.get_axis("ui_left","ui_right")
	preview_turntable.rotate_y(-spin * delta * 1.6)

func _clear_preview() -> void:
	if is_instance_valid(preview):
		preview.queue_free()
	preview = null
	preview_turntable = null
