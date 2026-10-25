extends RefCounted
## Original colour and silhouettes with smaller textures and inexpensive lighting.
const Geo = preload("res://scripts/planet_geometry.gd")
var world: Node3D

func configure(target: Node3D) -> void:
	world = target
	(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	var environment: Environment = (world.get_node("Environment") as WorldEnvironment).environment.duplicate()
	(world.get_node("Environment") as WorldEnvironment).environment = environment
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("668ca6")
	sky_material.sky_horizon_color = Color("c2d1ce")
	sky_material.ground_bottom_color = Color("526d6b")
	sky_material.ground_horizon_color = Color("c2d1ce")
	environment.sky = Sky.new()
	environment.sky.sky_material = sky_material
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_32
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c1ccd2")
	environment.ambient_light_energy = .42
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	(world.get_node("Sun") as DirectionalLight3D).light_energy = .75
	(world.get_node("Sun") as DirectionalLight3D).light_color = Color("fff0d8")

func apply(_node: Node) -> void:
	pass

func set_mobile_quality(_enabled: bool) -> void:
	pass

func update(up: Vector3, overview: bool) -> void:
	var axes: Basis = Geo.frame(Vector3.UP if overview else up)
	(world.get_node("Environment") as WorldEnvironment).environment.sky_rotation = axes.get_euler()
	(world.get_node("Sun") as DirectionalLight3D).global_basis = Basis.looking_at(-(axes * Vector3(-.5,.68,.45).normalized()), axes.z)
