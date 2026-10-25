extends Node3D
## One reusable exhibit gallery is resident at a time. Text is engine-native.

const Catalog = preload("res://scripts/university_catalog.gd")
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const REGION_COLORS: Array[Color] = [Color("698f91"), Color("859563"), Color("c58a64"), Color("7d9f86"), Color("779daa")]
var targets: Array[Dictionary] = []
var booth_positions: Dictionary = {}
var model_cache: Dictionary = {}
var catalog: RefCounted
var layout: Dictionary = {}
var region: String = ""
var page: int = 0
var labels: Array[Label3D] = []
var text_font: FontVariation
var kit_models: Dictionary = {}
var exhibit_errors: Array[String] = []

func _init() -> void:
	text_font = FontVariation.new()
	text_font.base_font = FONT
	text_font.variation_opentype = {2003265652: 550.0}

func configure(data: RefCounted, models: Dictionary, collision_layout: Dictionary) -> void:
	catalog = data
	model_cache = models
	layout = collision_layout
	_cache_exhibit_kit()

func _cache_exhibit_kit() -> void:
	kit_models.clear()
	if not model_cache.has("exhibit_kit"):
		return
	var source: Node3D = (model_cache.exhibit_kit as PackedScene).instantiate() as Node3D
	# Each authored module is one joined mesh. Packed scenes retain shared mesh
	# and PBR resources, while only the current eight exhibits enter the tree.
	for child: Node in source.get_children():
		if not child is Node3D:
			continue
		var packed: PackedScene = PackedScene.new()
		if packed.pack(child) == OK:
			kit_models[str(child.name)] = packed
	source.free()

func clear_space() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	targets.clear()
	booth_positions.clear()
	labels.clear()
	exhibit_errors.clear()

func _model(key: String, parent: Node3D, at: Vector3 = Vector3.ZERO) -> Node3D:
	var packed: PackedScene = kit_models.get(key, model_cache.get(key)) as PackedScene
	if packed == null:
		exhibit_errors.append("Missing model: " + key)
		return null
	var node: Node3D = packed.instantiate() as Node3D
	# Godot 4.7's importer retains COLOR_0 but can leave this material flag off.
	# Enable authored vertex tints only on surfaces that contain COLOR_0.
	# Textured PBR materials retain their original color, maps and roughness.
	var meshes: Array[Node] = node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		meshes.append(node)
	for child: Node in meshes:
		var instance: MeshInstance3D = child as MeshInstance3D
		for index: int in range(instance.mesh.get_surface_count()):
			var material: StandardMaterial3D = instance.get_active_material(index) as StandardMaterial3D
			if material != null and instance.mesh is ArrayMesh and (instance.mesh as ArrayMesh).surface_get_format(index) & Mesh.ARRAY_FORMAT_COLOR:
				material.vertex_color_use_as_albedo = true
				material.vertex_color_is_srgb = false
	parent.add_child(node)
	node.position = at
	return node

func _box(parent: Node3D, at: Vector3, size: Vector3, label_value: String) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = label_value
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = at
	parent.add_child(body)
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)

func _label3d(parent: Node3D, text_value: String, at: Vector3, size: int = 44, scale_value: float = .012, color: Color = Color("ead9b6")) -> Label3D:
	var node: Label3D = Label3D.new()
	node.text = text_value
	node.font = text_font
	node.font_size = size
	node.pixel_size = scale_value
	node.modulate = color
	node.outline_size = 0
	node.no_depth_test = false
	node.shaded = false
	node.double_sided = false
	node.position = at
	parent.add_child(node)
	labels.append(node)
	return node

func _target(id: String, label_value: String, kind: String, at: Vector3, extra: Dictionary = {}) -> void:
	var record: Dictionary = {"id":id, "label":label_value, "kind":kind, "position":at}
	record.merge(extra)
	targets.append(record)

func _boundaries(width: float, depth: float) -> void:
	_box(self, Vector3(0, -.15, 0), Vector3(width, .3, depth), "Floor")
	_box(self, Vector3(-width * .5, 1.5, 0), Vector3(.25, 3, depth), "WestBoundary")
	_box(self, Vector3(width * .5, 1.5, 0), Vector3(.25, 3, depth), "EastBoundary")
	_box(self, Vector3(0, 1.5, -depth * .5), Vector3(width, 3, .25), "NorthBoundary")
	_box(self, Vector3(0, 1.5, depth * .5), Vector3(width, 3, .25), "SouthBoundary")

func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func _authored_details(area: String) -> void:
	var config: Dictionary = layout.get(area, {})
	for obstacle: Dictionary in config.get("obstacles", []):
		_box(self, _vector(obstacle.center), _vector(obstacle.size), str(obstacle.name))
	for item: Dictionary in config.get("lights", []):
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "ReadingLight"
		lamp.position = _vector(item.position)
		lamp.light_color = Color(str(item.get("color", "ffd9a0")))
		lamp.light_energy = float(item.get("energy", 1.0))
		lamp.omni_range = float(item.get("range", 12.0))
		lamp.omni_attenuation = 1.4
		lamp.shadow_enabled = false
		add_child(lamp)

func build_atrium() -> void:
	clear_space()
	region = ""
	page = 0
	_model("atrium", self)
	_boundaries(32, 26)
	_authored_details("atrium")
	for index: int in range(5):
		var x: float = -12.0 + index * 6.0
		var region_id: String = Catalog.REGION_IDS[index]
		_label3d(self, Catalog.REGION_NAMES[index], Vector3(x, 4.18, -8.7), 42, .012, Color("f7f4e9"))
		_label3d(self, "%d 個校園條目" % catalog.region_entries(region_id).size(), Vector3(x, 3.55, -8.7), 28, .01)
		_target("region_" + region_id, "探索" + Catalog.REGION_NAMES[index] + "校園", "region", Vector3(x, 0, -7.7), {"region":region_id})
	_build_map()
	_label3d(self, "臺灣校園導覽", Vector3(0, 1.75, -.65), 34, .009)
	_label3d(self, "138 個探索條目", Vector3(0, 1.38, -.65), 22, .007)
	_target("map", "打開校園導覽地圖", "map", Vector3(0, 0, 2))
	_target("journal", "翻開我的收藏手冊", "journal", Vector3(5.8, 0, 5.8))
	_model("feature_book", self, Vector3(7, .65, 4.8))
	_label3d(self, "探索手冊", Vector3(7, 1.5, 4.6), 32, .008)
	_target("exit", "返回 3D 世界", "exit", Vector3(0, 0, 9.9))
	var exit_label: Label3D = _label3d(self, "返回 3D 世界", Vector3(0, 2.7, 10.63), 42, .012)
	exit_label.rotation.y = PI

func _build_map() -> void:
	var outline: PackedVector2Array = PackedVector2Array([Vector2(.48,-.9),Vector2(.24,-.8),Vector2(.09,-.54),Vector2(-.13,-.24),Vector2(-.34,.12),Vector2(-.37,.47),Vector2(-.23,.88),Vector2(-.07,.95),Vector2(.03,.61),Vector2(.2,.24),Vector2(.34,-.12),Vector2(.52,-.57)])
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(outline)
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(0, indices.size(), 3):
		for offset: int in [0, 2, 1]:
			var point: Vector2 = outline[indices[index + offset]]
			surface.set_normal(Vector3.UP)
			surface.add_vertex(Vector3(point.x * 1.4, .91, point.y * .91))
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = "TaiwanMap"
	mesh.mesh = surface.commit()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("5b9884")
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .85
	mesh.material_override = material
	add_child(mesh)
	var points: Array[Vector3] = [Vector3(.35,.95,-.52),Vector3(-.1,.95,-.05),Vector3(-.29,.95,.48),Vector3(.26,.95,.14),Vector3(-.92,.95,.23)]
	for index: int in range(points.size()):
		var dot: MeshInstance3D = MeshInstance3D.new()
		var sphere: SphereMesh = SphereMesh.new()
		sphere.radius = .055
		sphere.height = .11
		sphere.radial_segments = 10
		sphere.rings = 4
		dot.mesh = sphere
		dot.position = points[index]
		var dot_material: StandardMaterial3D = StandardMaterial3D.new()
		dot_material.albedo_color = REGION_COLORS[index]
		dot.material_override = dot_material
		add_child(dot)

func build_gallery(region_id: String, page_number: int) -> void:
	clear_space()
	region = region_id
	page = clampi(page_number, 0, catalog.page_count(region) - 1)
	_model("gallery", self)
	_boundaries(30, 38)
	_authored_details("gallery")
	var count: int = catalog.page_count(region)
	_label3d(self, "%s校園  /  展廊 %02d" % [Catalog.region_label(region), page + 1], Vector3(0, 4.15, -17.7), 42, .012)
	_label3d(self, "%d / %d   ·   每一種日常，都有自己的風景" % [page + 1, count], Vector3(0, 3.55, -17.7), 24, .01)
	var batch: Array[Dictionary] = catalog.page_entries(region, page)
	for index: int in range(batch.size()):
		_build_booth(batch[index], index)
	if page > 0:
		_target("previous", "前往上一間展廊", "page", Vector3(-7, 0, -14.8), {"page":page - 1})
		_label3d(self, "上一間展廊", Vector3(-7, 4.28, -15.7), 35, .012, Color("f7f4e9"))
	else:
		_target("region_map", "選擇其他地區", "map", Vector3(-7, 0, -14.8))
		_label3d(self, "其他地區", Vector3(-7, 4.28, -15.7), 35, .012, Color("f7f4e9"))
	if page + 1 < count:
		_target("next", "前往下一間展廊", "page", Vector3(7, 0, -14.8), {"page":page + 1})
		_label3d(self, "下一間展廊", Vector3(7, 4.28, -15.7), 35, .012, Color("f7f4e9"))
	else:
		_target("end_atrium", "回到中庭", "atrium", Vector3(7, 0, -14.8))
		_label3d(self, "中庭", Vector3(7, 4.28, -15.7), 35, .012, Color("f7f4e9"))
	_target("atrium", "回到中庭", "atrium", Vector3(0, 0, 16.6))
	var back: Label3D = _label3d(self, "中庭  /  導覽地圖", Vector3(0, 2.7, 17.5), 36, .012)
	back.rotation.y = PI

func _build_booth(entry: Dictionary, index: int) -> void:
	var left: bool = index % 2 == 0
	var row: int = index / 2
	var booth: Node3D = Node3D.new()
	booth.name = "School_" + str(entry.id)
	add_child(booth)
	booth.position = Vector3(-9 if left else 9, 0, 12 - row * 8)
	booth.rotation.y = PI * .5 if left else -PI * .5
	var profile: Dictionary = entry.get("art_profile", {})
	var display: String = str(profile.get("display_variant", ""))
	_model("display_" + display, booth)
	booth.set_meta("display_variant", display)
	booth.set_meta("composition", str(profile.get("composition", {}).get("id", "")))
	var miniature: Node3D = Node3D.new()
	miniature.name = "Diorama"
	booth.add_child(miniature)
	miniature.position = Vector3(0, .88, -.15)
	var modules: Array = profile.get("modules", [])
	if bool(layout.get("low_resources", false)):
		var primary: Array = profile.get("composition", {}).get("primary_modules", [])
		var selected_modules: Array = modules.filter(func(module: Dictionary) -> bool: return str(module.key) in primary).slice(0,4)
		for module: Dictionary in modules:
			if selected_modules.size() >= 4:
				break
			if module not in selected_modules:
				selected_modules.append(module)
		modules = selected_modules
	for module: Dictionary in modules:
		var part: Node3D = _model(str(module.key), miniature, _vector(module.position))
		if part == null:
			continue
		part.scale = _vector(module.get("scale", [1, 1, 1]))
		part.rotation.y = deg_to_rad(float(module.get("rotation_y", 0)))
		part.set_meta("source_cues", module.get("cue_ids", []))
	var booth_layout: Dictionary = layout.get("display_variants", {}).get(display, {})
	for obstacle: Dictionary in booth_layout.get("boxes", []):
		_box(booth, _vector(obstacle.center), _vector(obstacle.size), str(obstacle.name))
	var title_size: int = mini(42, floori(480.0 / maxf(str(entry.name).length(), 1)))
	var title: Label3D = _label3d(booth, str(entry.name), Vector3(0, 2.65, -1.24), title_size, .010, Color("f9eac9"))
	title.width = 490
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label3d(booth, str(entry.id) + "  /  " + " · ".join(entry.get("tags", []).slice(0, 3)), Vector3(0, 2.13, -1.22), 23, .008, Color("e4cc9e"))
	for section: int in range(5):
		var local_point: Vector3 = Vector3(-2 + section, 0, 2.05)
		var world_point: Vector3 = booth.to_global(local_point)
		_target(str(entry.id) + "_" + Catalog.SECTION_IDS[section], str(entry.name) + "・" + Catalog.SECTION_NAMES[section], "school", world_point, {"school_id":str(entry.id), "section":section})
		var tag: Label3D = _label3d(booth, ["位置", "周邊", "美食", "評價", "校風"][section], Vector3(-2 + section, .754, 1.39), 20, .0065)
		tag.modulate = Color("f5f0db")
	# Arrive just beside the centreline so the full-size avatar does not hide
	# the school's main miniature. The five physical objects remain in reach.
	booth_positions[str(entry.id)] = {"position":booth.to_global(Vector3(-.8, .08, 3)), "facing":-booth.basis.z, "yaw":booth.rotation.y}
	_target(str(entry.id) + "_overview", "認識" + str(entry.name), "overview", booth.to_global(Vector3(-.8, 0, 3)), {"school_id":str(entry.id), "section":-1})

func nearest(point: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = 1.85
	for target: Dictionary in targets:
		var delta: Vector3 = point - (target.position as Vector3)
		delta.y = 0
		var length: float = delta.length()
		if length < distance:
			distance = length
			best = target
	return best

func update_label_visibility(point: Vector3) -> void:
	for label_node: Label3D in labels:
		label_node.visible = label_node.global_position.distance_squared_to(point) < 32.0 * 32.0
