extends SceneTree

# Compatibility's per-object limit is independent for each positional-light
# type, not the sum of omni + spot lights. The current room has 4 omni + 1 spot.
# These caps reduce MAX_FORWARD_LIGHTS / MAX_LIGHT_DATA_STRUCTS shader arrays
# while retaining every authored light and all existing shadow settings.
# https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-rendering-limits-opengl-max-lights-per-object
# https://github.com/godotengine/godot/blob/4.7/drivers/gles3/rasterizer_scene_gles3.cpp
const OUTPUT: String = "res://../deliverables/performance/render-light-limits-checks.json"
var checks: Array[Dictionary] = []
var failures: int = 0
var per_type: int = 0
var total_limit: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label, "passed":passed, "evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func light_counts(node: Node) -> Dictionary:
	var counts: Dictionary = {"omni":0, "spot":0, "area":0, "directional":0}
	for light: Node in node.find_children("*", "Light3D", true, false):
		# Object inspection has its own World3D and its own rendering pass.
		var ancestor: Node = light.get_parent()
		var separate_world: bool = false
		while ancestor != null and ancestor != node:
			if ancestor is SubViewport and (ancestor as SubViewport).own_world_3d:
				separate_world = true
				break
			ancestor = ancestor.get_parent()
		if separate_world:
			continue
		if light is OmniLight3D:
			counts.omni += 1
		elif light is SpotLight3D:
			counts.spot += 1
		elif light is DirectionalLight3D:
			counts.directional += 1
		elif light.get_class() == "AreaLight3D":
			counts.area += 1
	return counts

func within_limits(label: String, counts: Dictionary) -> void:
	for kind: String in ["omni", "spot", "area"]:
		check(label + " " + kind + " count fits the per-type shader limit", int(counts[kind]) <= per_type, counts)
	check(label + " positional lights fit the renderable capacity", int(counts.omni) + int(counts.spot) + int(counts.area) <= total_limit, counts)

func run() -> void:
	per_type = int(ProjectSettings.get_setting("rendering/limits/opengl/max_lights_per_object"))
	total_limit = int(ProjectSettings.get_setting("rendering/limits/opengl/max_renderable_lights"))
	check("Compatibility renderer remains selected", ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility")
	check("Shader limits are the measured-scene budgets", per_type == 4 and total_limit == 8)
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(world)
	var world_counts: Dictionary = light_counts(world)
	within_limits("Outdoor world", world_counts)
	check("Both authored outdoor directional lights remain", int(world_counts.directional) == 2, world_counts)
	check("Outdoor scene adds no positional lights", int(world_counts.omni) + int(world_counts.spot) + int(world_counts.area) == 0, world_counts)
	world.free()
	world = null
	var room: Node3D = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
	room.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(room)
	var room_counts: Dictionary = light_counts(room)
	within_limits("Fully configured training room", room_counts)
	check("Ceiling spot, projector spill, reading lamp and both fills are included", int(room_counts.omni) == 4 and int(room_counts.spot) == 1 and int(room_counts.directional) == 1, room_counts)
	check("The authored ceiling shadow remains enabled", (room.get_node("DownwardCeilingLight") as SpotLight3D).shadow_enabled)
	check("Per-type limits preserve all five positional lights", int(room_counts.omni) + int(room_counts.spot) > per_type and int(room_counts.omni) <= per_type and int(room_counts.spot) <= per_type, room_counts)
	var furniture: Node3D = room.get("furniture_actions") as Node3D
	var model: Node3D = room.get("room_model") as Node3D
	var source: Node3D = model.find_child("*", true, false) as Node3D
	check("Inspection has an authored preview source", source != null)
	if source != null:
		furniture.call("_make_preview", source)
		var preview: SubViewport = furniture.get("preview") as SubViewport
		check("Inspection keeps a separate World3D", preview != null and preview.own_world_3d)
		if preview != null:
			var preview_counts: Dictionary = light_counts(preview)
			within_limits("Object inspection", preview_counts)
			check("Inspection directional light remains", int(preview_counts.directional) == 1, preview_counts)
		check("Inspection does not change the room's positional budget", light_counts(room) == room_counts)
	room.free()
	room = null
	await process_frame
	await process_frame
	var report: Dictionary = {"passed":failures == 0, "failed":failures, "per_type_limit":per_type, "renderable_limit":total_limit, "world":world_counts, "room":room_counts, "checks":checks}
	FileAccess.open(OUTPUT, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RENDER_LIGHT_LIMIT_CHECKS ", JSON.stringify(report))
	quit(1 if failures > 0 else 0)
