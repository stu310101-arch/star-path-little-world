extends SceneTree

const ArtDirection = preload("res://scripts/world_art_direction.gd")
const OUTPUT: String = "res://../deliverables/mobile-optimization/world-quality-checks.json"
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func run() -> void:
	var original_fps: int = Engine.max_fps
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	var settings: Node = world.get("graphics_settings") as Node
	var settings_path: String = "user://mobile_world_quality_%d.cfg" % Time.get_ticks_usec()
	settings.set("settings_path", settings_path)
	var art: RefCounted = world.get("art_direction") as RefCounted
	var camera: Camera3D = world.get("camera") as Camera3D
	var materials: Dictionary = art.get("materials") as Dictionary
	check("Production world has shared authored surface materials", materials.size() >= 2, materials.size())
	var snapshot: Dictionary = {}
	for key: String in materials:
		var material: ShaderMaterial = materials[key] as ShaderMaterial
		snapshot[key] = {}
		for uniform: String in ["surface_color", "surface_normal", "surface_roughness", "bank_soil", "bank_rock", "world_scale", "surface_kind", "biome_tint", "biome_index", "tint"]:
			snapshot[key][uniform] = material.get_shader_parameter(uniform)
	settings.set("_mobile_web", true)
	settings.call("restore_defaults")
	var mobile_applied: bool = bool(world.get("mobile_quality"))
	for material: ShaderMaterial in materials.values():
		mobile_applied = mobile_applied and material.shader == ArtDirection.MobileSurface
	check("Restoring mobile defaults switches every existing terrain material", mobile_applied)
	check("Mobile overview retains the complete planet", camera.far >= float(world.get("layout").radius) * 6.0 and camera.near > 1.0, {"near": camera.near, "far": camera.far})
	world.set("overview", false)
	world.call("update_camera_clipping")
	check("Mobile roaming bounds draw distance and preserves nearby geometry", camera.far <= 160.0 and is_equal_approx(camera.near, 0.1), {"near": camera.near, "far": camera.far})
	check("Mobile quality preserves the authored clear atmosphere", is_equal_approx((art.get("environment") as Environment).fog_density, 0.0018))
	settings.call("set_quality_profile", "standard")
	var restored: bool = not bool(world.get("mobile_quality"))
	for key: String in materials:
		var material: ShaderMaterial = materials[key] as ShaderMaterial
		restored = restored and material.shader == ArtDirection.Surface
		for uniform: String in snapshot[key]:
			restored = restored and material.get_shader_parameter(uniform) == snapshot[key][uniform]
	check("Returning to standard restores full shaders without losing authored uniforms", restored)
	check("Standard roaming restores the original far plane and fog", camera.far >= float(world.get("layout").radius) * 6.0 and is_equal_approx((art.get("environment") as Environment).fog_density, 0.0018), camera.far)
	# A streamed material can first be created while the cheaper shader is active.
	# Its currently unused normal/roughness values must survive a later upgrade.
	var late_art: RefCounted = ArtDirection.new()
	late_art.call("set_mobile_quality", true)
	var late_asphalt: ShaderMaterial = late_art.call("material_for", "asphalt") as ShaderMaterial
	check("Late-created material immediately uses the mobile shader", late_asphalt.shader == ArtDirection.MobileSurface)
	late_art.call("set_mobile_quality", false)
	check("Late-created material retains normal and roughness maps after upgrade", late_asphalt.get_shader_parameter("surface_normal") == ArtDirection.MAPS.bed[1] and late_asphalt.get_shader_parameter("surface_roughness") == ArtDirection.MAPS.bed[2])
	check("Late-created asphalt retains its authored bump and scale after upgrade", is_equal_approx(float(late_asphalt.get_shader_parameter("bump_strength")), 0.065) and is_equal_approx(float(late_asphalt.get_shader_parameter("world_scale")), 4.0))
	settings.call("set_quality_profile", "balanced")
	world.set("overview", true)
	world.call("update_camera_clipping")
	check("Returning from mobile roaming to overview restores full planet visibility", camera.far >= float(world.get("layout").radius) * 6.0)
	# Exercise the actual JS-to-Godot input seam and player velocity. A partially
	# deflected joystick must walk proportionally rather than snap to full speed.
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.set_physics_process(false)
	player.set_process(false)
	player.controls_enabled = true
	player.land_only = false
	player.gravity_strength = 0.0
	player.teleport(Vector3.UP, player.planet_radius + 30.0)
	var bridge: Node = root.get_node("WebTouch")
	await physics_frame
	bridge.call("_touch", ["axis", 0.0, -0.5])
	player.call("_physics_process", 1.0 / 60.0)
	var half_speed: float = player.velocity.slide(Vector3.UP).length()
	check("Half joystick deflection produces half walking speed", absf(half_speed - player.walk_speed * 0.5) < 0.01, half_speed)
	bridge.call("_touch", ["axis", 0.0, -1.0])
	player.call("_physics_process", 1.0 / 60.0)
	var full_speed: float = player.velocity.slide(Vector3.UP).length()
	check("Full joystick deflection produces full walking speed", absf(full_speed - player.walk_speed) < 0.01, full_speed)
	bridge.call("_touch", ["axis", 0.0, 0.0])
	player.call("_physics_process", 1.0 / 60.0)
	check("Releasing the joystick clears player tangent velocity", player.velocity.length() < 0.001, player.velocity.length())
	var output_path: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	output.store_string(JSON.stringify({"engine": Engine.get_version_info(), "checks": checks, "failures": failures}, "\t"))
	output.close()
	world.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path))
	Engine.max_fps = original_fps
	print("MOBILE_WORLD_QUALITY_CHECKS ", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
