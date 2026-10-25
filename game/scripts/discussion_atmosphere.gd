extends RefCounted
## Shared-world daylight with an inexpensive sky and distant atmospheric depth.
const SKY: Shader = preload("res://shaders/world_sky.gdshader")
const WATER: Shader = preload("res://shaders/discussion_water.gdshader")

static func finish_surfaces(art: Node3D) -> void:
	var water := ShaderMaterial.new()
	water.shader = WATER
	for node: Node in art.find_children("*","MeshInstance3D",true,false):
		var mesh := node as MeshInstance3D
		for index: int in range(mesh.mesh.get_surface_count()):
			var material: Material = mesh.get_active_material(index)
			if material != null and material.resource_name == "MAT_Garden_water":
				mesh.set_surface_override_material(index,water)

static func build(room: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_material := ShaderMaterial.new()
	sky_material.shader = SKY
	environment.sky.sky_material = sky_material
	environment.sky.radiance_size = Sky.RADIANCE_SIZE_128
	environment.sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c4d6df")
	environment.ambient_light_energy = .32
	environment.ambient_light_sky_contribution = 0.0
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.fog_enabled = true
	environment.fog_light_color = Color("b6c9cb")
	environment.fog_density = .0028
	environment.fog_sky_affect = .10
	var world_environment := WorldEnvironment.new()
	world_environment.name = "GardenEnvironment"
	world_environment.environment = environment
	room.add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.name = "GardenSun"
	sun.rotation_degrees = Vector3(-43,-28,0)
	sun.light_color = Color("fff1db")
	sun.light_energy = .52
	sun.light_angular_distance = .8
	sun.shadow_bias = .18
	sun.shadow_normal_bias = 2.0
	sun.shadow_opacity = .78
	sun.directional_shadow_max_distance = 38.0
	room.add_child(sun)
