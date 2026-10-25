extends RefCounted

## Shared art system for all six districts; apply once as each region streams in.
## Source meshes/collision stay editable. No per-frame geometry scans.
const Geo = preload("res://scripts/planet_geometry.gd")
const Surface = preload("res://shaders/world_surface.gdshader")
const MobileSurface = preload("res://shaders/world_surface_mobile.gdshader")
const SkyShader = preload("res://shaders/world_sky.gdshader")
const Architecture = preload("res://scripts/world_architecture.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
var architecture: RefCounted = Architecture.new()
const StreetFurniture = preload("res://scripts/world_street_furniture.gd")
var street_furniture: RefCounted = StreetFurniture.new()
const MAPS := {
	"ground": [preload("res://assets/world_materials/leafy_grass_diffuse.jpg"),preload("res://assets/world_materials/leafy_grass_nor_gl.jpg"),preload("res://assets/world_materials/leafy_grass_rough.jpg")],
	"bed": [preload("res://assets/world_materials/forest_ground_04_diffuse.jpg"),preload("res://assets/world_materials/forest_ground_04_nor_gl.jpg"),preload("res://assets/world_materials/forest_ground_04_rough.jpg")],
	"stone": [preload("res://assets/world_materials/cobblestone_floor_03_diffuse.jpg"),preload("res://assets/world_materials/cobblestone_floor_03_nor_gl.jpg"),preload("res://assets/world_materials/cobblestone_floor_03_rough.jpg")],
	"timber": [preload("res://assets/world_materials/wooden_planks_diffuse.jpg"),preload("res://assets/world_materials/wooden_planks_nor_gl.jpg"),preload("res://assets/world_materials/wooden_planks_rough.jpg")],
	"rock": [preload("res://assets/world_materials/rocky_terrain_02_diffuse.jpg"),preload("res://assets/world_materials/rocky_terrain_02_nor_gl.jpg"),preload("res://assets/world_materials/rocky_terrain_02_rough.jpg")]
}
var materials: Dictionary = {}
var world: Node3D
var environment: Environment
var sun: DirectionalLight3D
var fill: DirectionalLight3D
var last_up := Vector3.ZERO
var previous_overview := false
var mobile_quality: bool = false

func set_mobile_quality(enabled: bool) -> void:
	mobile_quality = enabled
	for material: ShaderMaterial in materials.values():
		material.shader = MobileSurface if enabled else Surface

func configure(target: Node3D) -> void:
	world=target
	environment=(world.get_node("Environment") as WorldEnvironment).environment.duplicate()
	(world.get_node("Environment") as WorldEnvironment).environment=environment
	var sky_material:=ShaderMaterial.new()
	sky_material.shader=SkyShader
	environment.sky=Sky.new()
	environment.sky.sky_material=sky_material
	environment.sky.radiance_size=Sky.RADIANCE_SIZE_128
	environment.sky.process_mode=Sky.PROCESS_MODE_INCREMENTAL
	environment.background_mode=Environment.BG_SKY
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=Color("c1ccd2")
	environment.ambient_light_energy=0.30
	environment.reflected_light_source=Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure=1.0
	environment.fog_light_color=Color("b9c7c8")
	environment.fog_density=0.0018
	environment.fog_sky_affect=0.12
	sun=world.get_node("Sun") as DirectionalLight3D
	sun.light_color=Color("fff0d8")
	sun.light_energy=0.68
	sun.light_angular_distance=1.2
	sun.shadow_bias=0.4
	sun.shadow_normal_bias=1.6
	sun.shadow_opacity=0.85
	fill=world.get_node("Fill") as DirectionalLight3D
	fill.light_color=Color("bbcfdf")
	fill.light_energy=0.06
	for label: String in ["Globe","Neighborhood","Stations"]:
		apply(world.get_node(label))
	update(Vector3.UP,true)

func material_for(kind: String,biome: String="") -> Material:
	var key: String=kind+":"+biome
	if materials.has(key):
		return materials[key] as Material
	var source: String=kind if MAPS.has(kind) else "bed" if kind=="asphalt" else "stone"
	var mat:=ShaderMaterial.new()
	mat.shader=MobileSurface if mobile_quality else Surface
	mat.set_shader_parameter("surface_color",MAPS[source][0])
	mat.set_shader_parameter("surface_normal",MAPS[source][1])
	mat.set_shader_parameter("surface_roughness",MAPS[source][2])
	mat.set_shader_parameter("bank_soil",MAPS.bed[0])
	mat.set_shader_parameter("bank_rock",MAPS.rock[0])
	mat.set_shader_parameter("world_scale",0.50 if kind=="ground" else 0.46 if kind=="stone" else 0.50 if kind=="timber" else 0.32 if kind=="bed" else 0.12)
	mat.set_shader_parameter("surface_kind",1 if kind=="ground" else 0)
	if kind=="ground" and not biome.is_empty():
		var tone: Array=Biomes.spec(biome).get("ground_tint",[.38,.51,.33])
		mat.set_shader_parameter("biome_tint",Vector3(tone[0],tone[1],tone[2]))
		mat.set_shader_parameter("biome_index",["counseling","admissions","recommendations","universities","life","wordking"].find(biome))
	if kind=="asphalt":
		mat.set_shader_parameter("surface_kind",2)
		mat.set_shader_parameter("world_scale",4.0)
		mat.set_shader_parameter("bump_strength",.065)
	if kind=="stone":
		mat.set_shader_parameter("tint",Color(.74,.78,.79))
	elif kind=="timber":
		mat.set_shader_parameter("tint",Color(.76,.72,.64))
	elif kind=="bed":
		mat.set_shader_parameter("tint",Color(.36,.45,.39))
	elif kind=="rock":
		mat.set_shader_parameter("tint",Color(.58,.56,.50))
		mat.set_shader_parameter("world_scale",.34)
	materials[key]=mat
	return mat

func apply(node: Node) -> void:
	if node is Node3D:
		architecture.call("apply",node)
		street_furniture.call("apply",node)
	_apply_surfaces(node)

func _apply_surfaces(node: Node) -> void:
	if node is MeshInstance3D:
		var mi:=node as MeshInstance3D
		var label:=str(mi.get_meta("authored_surface",mi.name)).to_lower()
		if label=="ocean":
			# The full water sphere must not expand the sun's caster depth range.
			mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif "contouredbanks" in label or label=="land":
			mi.material_override=material_for("ground",str(mi.get_meta("biome_station","")))
		elif "shallowwaterbed" in label:
			mi.material_override=material_for("bed")
		elif "naturalrockbankslopes" in label or "shorerockstrata" in label or "biomerockoutcrop" in label:
			mi.material_override=material_for("rock")
		elif label=="asphalt":
			mi.material_override=material_for("asphalt")
		elif "timber" in label or label=="deck" or "deckfascia" in label or "boardwalkrails" in label:
			mi.material_override=material_for("timber")
		elif ("sidewalk" in label and not "joints" in label) or "promenade" in label or "forecourt" in label or "civicplaza" in label or "paving" in label or "arrivalwalkway" in label or label in ["foundation","platform","stonewalk","townapproach"]:
			mi.material_override=material_for("stone")
	# Never walk into character skeletons or mutate imported mesh resources.
	for child: Node in node.get_children():
		_apply_surfaces(child)

func update(up: Vector3,overview: bool) -> void:
	if last_up.distance_squared_to(up)<0.00002 and previous_overview==overview:
		return
	last_up=up
	previous_overview=overview
	(environment.sky.sky_material as ShaderMaterial).set_shader_parameter("overview_mode",overview)
	var axes: Basis=Geo.frame(Vector3.UP if overview else up)
	environment.sky_rotation=axes.get_euler()
	environment.fog_enabled=not overview
	environment.ambient_light_energy=0.48 if overview else 0.30
	fill.light_energy=0.16 if overview else 0.06
	var light_direction: Vector3=axes*Vector3(-.5,.68,.45).normalized()
	sun.global_basis=Basis.looking_at(-light_direction,axes.z)
	fill.global_basis=Basis.looking_at((axes*Vector3(.5,-.4,.4)).normalized(),axes.z)
