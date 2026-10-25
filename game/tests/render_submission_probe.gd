extends Node

## Diagnostic-only renderer ablation. The product scene and assets are not edited.
## Each ablation is bracketed by restored baselines; simulation is frozen for all
## bracketed phases so animation/culling cannot undo temporary render-layer edits.
const Fixture = preload("res://tests/startup_fixture.gd")
var world: Node3D
var settings: Node
var tree: SceneTree
var viewport: Window
var output: String
var inventory_only: bool = false
var sample_ms: int = 1000
var profiles: PackedStringArray = ["standard", "low", "mobile"]
var views: PackedStringArray = ["overview", "waterfront_0"]
var categories: PackedStringArray = ["ui", "terrain", "architecture", "vegetation", "labels", "traffic", "shadows", "avatar", "mixed_overview", "other"]
var report: Dictionary = {"errors": [], "runs": [], "status": "initializing"}
var records: Array[Dictionary] = []
var mesh_stats: Dictionary = {}
var material_signatures: Dictionary = {}

func _ready() -> void:
	call_deferred("run")

func option(key: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--" + key + "="):
			return arg.substr(key.length() + 3)
	if OS.has_feature("web"):
		var value: Variant = JavaScriptBridge.eval("new URL(location.href).searchParams.get(" + JSON.stringify(key) + ")")
		if value is String and not str(value).is_empty():
			return str(value)
	return fallback

func run() -> void:
	tree = get_tree()
	viewport = tree.root
	inventory_only = OS.get_cmdline_user_args().has("--inventory-only")
	profiles = option("profiles", "standard" if inventory_only else "standard,low,mobile").split(",")
	views = option("views", "overview,waterfront_0").split(",")
	categories = option("categories", ",".join(categories)).split(",")
	sample_ms = clampi(int(option("sample-ms", "1000")), 250, 5000)
	output = ProjectSettings.globalize_path("res://../deliverables/render-budget/" + option("label", "submission-ablation"))
	if not OS.has_feature("web"):
		DirAccess.make_dir_recursive_absolute(output)
	viewport.size = Vector2i(1280, 800)
	viewport.gui_disable_input = true
	if DisplayServer.get_name() == "headless" and not inventory_only:
		report.errors.append("Renderer measurement requires a real renderer. Use --inventory-only for headless.")
		finish()
		return
	if not inventory_only:
		if not OS.has_feature("web"):
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	report.merge({
		"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "web": OS.has_feature("web"),
		"inventory_only": inventory_only, "sample_ms": sample_ms,
		"method": "Diagnostic only: same-process fixed view; freeze simulation for every A/B/A phase. Geometry uses layer=0, UI hides CanvasLayers, shadows disable Light3D shadows. No product optimization is applied.",
		"limits": "Surface counts are candidates, not actual draws. Mixed distant overview batches cannot be assigned to one semantic category. Web GPU timer zero is unavailable, not a fast GPU result. Baseline/live differs from frozen phases by simulation and is labeled separately.",
		"pixel_contract": "1280x800, scale=1, MSAA_2X for ALL profiles. Profile lighting/material/mesh policy remains otherwise unchanged. Graphics adaptive signal disconnected only in this test.",
	})
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	viewport.add_child(world)
	tree.current_scene = world
	settings = world.get("graphics_settings") as Node
	settings.set("settings_path", "user://render_submission_probe.cfg")
	# This is connected to SceneTree, so process_mode alone does not disable it.
	var adaptive: Callable = Callable(settings, "_sample_render_frame")
	if tree.process_frame.is_connected(adaptive):
		tree.process_frame.disconnect(adaptive)
	world.set_process_input(false)
	world.set_process_unhandled_input(false)
	for profile: String in profiles:
		world.process_mode = Node.PROCESS_MODE_INHERIT
		settings.set("_mobile_web", profile == "mobile")
		settings.call("set_quality_profile", profile)
		settings.call("set_msaa_enabled", true)
		settings.call("set_frame_limit", 90)
		pin_pixels()
		for view: String in views:
			world.process_mode = Node.PROCESS_MODE_INHERIT
			if view == "overview":
				world.call("set_overview", true)
			else:
				world.call("setup_water_review", int(view.trim_prefix("waterfront_")), false)
				if not await Fixture.wait_roaming(world, tree):
					report.errors.append("Preparation failed: " + profile + "/" + view)
					continue
			pin_pixels()
			await tree.create_timer(.7 if inventory_only else 1.5).timeout
			pin_pixels()
			var row: Dictionary = {"profile": profile, "view": view, "phases": []}
			if not inventory_only:
				row.phases.append(await sample("live_baseline"))
			world.process_mode = Node.PROCESS_MODE_DISABLED
			pin_pixels()
			await tree.process_frame
			row.camera_transform = str((world.get("camera") as Camera3D).global_transform)
			row.streaming = world.get("streaming").call("metrics")
			row.inventory = inventory()
			if not inventory_only:
				row.phases.append(await phase("baseline_start"))
				for category: String in categories:
					var saved: Array[Dictionary] = disable_category(category)
					var result: Dictionary = await phase("without_" + category)
					result.changed_nodes = saved.size()
					row.phases.append(result)
					restore(saved)
					row.phases.append(await phase("restored_" + category))
			report.runs.append(row)
			save_report()
			print("SUBMISSION_RUN ", profile, " ", view, " nodes=", records.size())
	finish()

func pin_pixels() -> void:
	viewport.content_scale_size = Vector2i(1280, 800)
	viewport.scaling_3d_scale = 1.0
	viewport.msaa_3d = Viewport.MSAA_2X
	Engine.max_fps = 0

func phase(label: String) -> Dictionary:
	await tree.create_timer(.2).timeout
	return await sample(label)

func sample(label: String) -> Dictionary:
	var values: Dictionary = {"frame": [], "gpu": [], "render_cpu": [], "process": [], "physics": [], "draws": [], "primitives": []}
	var foreground_start: Dictionary = browser_foreground()
	var stalled_frames: int = 0
	var deadline: int = Time.get_ticks_msec() + sample_ms
	var previous: int = Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await tree.process_frame
		var now: int = Time.get_ticks_usec()
		var elapsed_ms: float = float(now - previous) / 1000.0
		values.frame.append(elapsed_ms)
		if elapsed_ms > 250.0:
			stalled_frames += 1
		previous = now
		values.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		values.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
		values.process.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		values.physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		values.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		values.primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var row: Dictionary = {"phase": label, "frames": values.frame.size(), "effective_scale": viewport.scaling_3d_scale,
		"effective_msaa": viewport.msaa_3d, "viewport": [viewport.size.x, viewport.size.y],
		"engine_frame_cap": Engine.max_fps, "camera": str((world.get("camera") as Camera3D).global_transform),
		"foreground_start": foreground_start, "foreground_end": browser_foreground(),
		"frames_over_250ms": stalled_frames, "invalid_reasons": []}
	if OS.has_feature("web"):
		if bool(foreground_start.get("hidden", true)) or bool(row.foreground_end.get("hidden", true)):
			row.invalid_reasons.append("browser_document_hidden")
		if not bool(foreground_start.get("focused", false)) or not bool(row.foreground_end.get("focused", false)):
			row.invalid_reasons.append("browser_document_not_focused")
		if stalled_frames > 0:
			row.invalid_reasons.append("frames_over_250ms_possible_throttling_or_stall")
	row.timing_valid = row.invalid_reasons.is_empty()
	for key: String in values:
		var samples: Array = values[key]
		samples.sort()
		row[key + "_median"] = samples[samples.size() / 2]
		row[key + "_p95"] = samples[mini(samples.size() - 1, ceili(samples.size() * .95) - 1)]
	row.gpu_timer_available = not inventory_only and float(row.gpu_median) > 0.0
	if not row.gpu_timer_available:
		row.gpu_median = null
		row.gpu_p95 = null
	if viewport.size != Vector2i(1280, 800) or viewport.scaling_3d_scale != 1.0 or viewport.msaa_3d != Viewport.MSAA_2X:
		report.errors.append("Pixel contract violated in " + label)
	print("SUBMISSION_PHASE ", label, " frame=", row.frame_median, " cpu=", row.render_cpu_median, " gpu=", row.gpu_median, " draws=", row.draws_median)
	return row

func browser_foreground() -> Dictionary:
	if not OS.has_feature("web"):
		return {"scope": "native"}
	var state: Variant = JavaScriptBridge.eval("JSON.stringify({hidden:document.hidden,focused:document.hasFocus(),visibility:document.visibilityState})")
	return JSON.parse_string(str(state)) as Dictionary if state is String else {"unavailable": true}

func classify(node: GeometryInstance3D) -> String:
	var path: String = str(world.get_path_to(node)).to_lower()
	if path.begins_with("player/"):
		return "avatar"
	if node is Label3D:
		return "labels"
	# Semantic source has been irreversibly material-batched in these meshes.
	# Keep it separate rather than falsely calling all far scenery "buildings".
	if path.contains("overview_") or path.contains("bakedsilhouette"):
		return "mixed_overview"
	if path.contains("citytraffic") or path.contains("oceanlife") or path.contains("lakefish"):
		return "traffic"
	var kind: String = str(node.get_meta("ecology_kind", node.get_meta("aquatic_kind", "")))
	if not kind.is_empty():
		return "terrain" if kind == "bank_stones" else "vegetation"
	# District names and StreetLight are not semantic vegetation evidence.
	var semantic: PackedStringArray = []
	for component: String in path.split("/"):
		if not component.begins_with("detail_"):
			semantic.append(component.replace("street", ""))
	path = "/".join(semantic)
	for token: String in ["tree", "birch", "alder", "willow", "pine", "blossom", "flower", "fern", "cattail", "waterlily", "water_lily", "shrub", "reed", "grass", "fineleaf", "planting"]:
		if path.contains(token) and not path.contains("bank_stones"):
			return "vegetation"
	for token: String in ["house", "building", "architectur", "station", "townhall", "roof", "tower", "window", "facade", "wall"]:
		if path.contains(token):
			return "architecture"
	for token: String in ["ground", "land", "ocean", "lake", "river", "water", "terrain", "bank", "bed", "slope", "paving", "sidewalk", "asphalt", "road", "promenade", "rock", "beach", "pavement", "plaza", "boardwalk", "deck"]:
		if path.contains(token):
			return "terrain"
	return "other"

func inventory() -> Dictionary:
	records.clear()
	material_signatures.clear()
	var groups: Dictionary = {}
	var repeated: Dictionary = {}
	var materials: Dictionary = {}
	var all_rows: Array[Dictionary] = []
	for raw: Node in world.find_children("*", "GeometryInstance3D", true, false):
		var node: GeometryInstance3D = raw as GeometryInstance3D
		var mesh: Mesh
		var count: int = 1
		if node is MeshInstance3D:
			mesh = (node as MeshInstance3D).mesh
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
			mesh = multi.mesh
			count = multi.instance_count if multi.visible_instance_count < 0 else multi.visible_instance_count
		var category: String = classify(node)
		records.append({"node": node, "category": category})
		var enabled: bool = node.is_visible_in_tree() and node.layers != 0
		var color: bool = enabled and node.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var stats: Dictionary = mesh_info(mesh)
		if not groups.has(category):
			groups[category] = {"nodes": 0, "enabled_nodes": 0, "color_nodes": 0, "enabled_surfaces": 0, "enabled_triangles": 0, "multimesh_instances": 0}
		var group: Dictionary = groups[category]
		group.nodes += 1
		if enabled:
			group.enabled_nodes += 1
			group.enabled_surfaces += stats.surfaces
			group.enabled_triangles += stats.triangles * count
			group.multimesh_instances += count if node is MultiMeshInstance3D else 0
		if color:
			group.color_nodes += 1
		var active_materials: Array[String] = []
		for surface: int in range(stats.surfaces):
			var material: Material = (node as MeshInstance3D).get_active_material(surface) if node is MeshInstance3D else (node.material_override if node.material_override != null else mesh.surface_get_material(surface))
			var signature: String = material_key(material)
			active_materials.append(signature)
			if not enabled:
				continue
			if not materials.has(signature):
				materials[signature] = {"signature": signature, "type": material.get_class() if material != null else "null", "surfaces": 0, "resource_ids": {}, "examples": []}
			var matrow: Dictionary = materials[signature]
			matrow.surfaces += 1
			matrow.resource_ids[str(material.get_instance_id() if material != null else 0)] = true
			if matrow.examples.size() < 4:
				matrow.examples.append(str(world.get_path_to(node)))
		if enabled and mesh != null and node is MeshInstance3D and (node as MeshInstance3D).skin == null:
			var key: String = str(mesh.get_instance_id()) + "/" + ",".join(active_materials) + "/shadow=" + str(node.cast_shadow) + "/layers=" + str(node.layers)
			if not repeated.has(key):
				repeated[key] = {"mesh": mesh.resource_path, "nodes": 0, "surfaces_per_node": stats.surfaces, "triangles_per_node": stats.triangles, "examples": []}
			var duplicate: Dictionary = repeated[key]
			duplicate.nodes += 1
			if duplicate.examples.size() < 5:
				duplicate.examples.append(str(world.get_path_to(node)))
		all_rows.append({"path": str(world.get_path_to(node)), "category": category, "type": node.get_class(), "enabled": enabled, "color": color, "layers": node.layers, "shadow": node.cast_shadow, "mesh": mesh.resource_path if mesh != null else "", "surfaces": stats.surfaces, "triangles": stats.triangles * count, "instances": count, "materials": active_materials})
	var material_rows: Array = materials.values()
	material_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.surfaces) > int(b.surfaces))
	for material: Dictionary in material_rows:
		material.distinct_resource_count = material.resource_ids.size()
		material.erase("resource_ids")
	var repeated_rows: Array = []
	for repeat: Dictionary in repeated.values():
		if repeat.nodes > 1:
			repeated_rows.append(repeat)
	repeated_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.nodes) * int(a.surfaces_per_node) > int(b.nodes) * int(b.surfaces_per_node))
	return {"groups": groups, "material_signatures": material_rows, "repeated_shared_mesh_candidates": repeated_rows,
		"geometry": all_rows if not OS.has_feature("web") else [],
		"limits": "Enabled candidates include off-frustum and shadow-only objects. Counts do not claim engine draw count. Material signatures include stored properties/resources, but sharing or batching still requires transform, transparency, skinning and per-instance uniform review."}

func mesh_info(mesh: Mesh) -> Dictionary:
	if mesh == null:
		return {"surfaces": 0, "triangles": 0}
	var id: int = mesh.get_instance_id()
	if mesh_stats.has(id):
		return mesh_stats[id] as Dictionary
	var triangles: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
	var result: Dictionary = {"surfaces": mesh.get_surface_count(), "triangles": triangles}
	mesh_stats[id] = result
	return result

func material_key(material: Material) -> String:
	if material == null:
		return "null"
	var id: int = material.get_instance_id()
	if material_signatures.has(id):
		return str(material_signatures[id])
	var properties: PackedStringArray = [material.get_class()]
	for item: Dictionary in material.get_property_list():
		var key: String = str(item.name)
		if int(item.usage) & PROPERTY_USAGE_STORAGE == 0 or key in ["resource_name", "resource_path", "resource_local_to_scene"]:
			continue
		var value: Variant = material.get(key)
		if value is Resource:
			var resource: Resource = value as Resource
			properties.append(key + "=" + (resource.resource_path if not resource.resource_path.is_empty() else str(resource.get_instance_id())))
		else:
			properties.append(key + "=" + var_to_str(value))
	properties.sort()
	var signature: String = "\n".join(properties).sha256_text()
	material_signatures[id] = signature
	return signature

func disable_category(category: String) -> Array[Dictionary]:
	var saved: Array[Dictionary] = []
	if category == "minimap":
		var hud: Node = world.get("hud") as Node
		var minimap: Control = hud.get("minimap") as Control if is_instance_valid(hud) else null
		if is_instance_valid(minimap):
			saved.append({"node": minimap, "property": "visible", "value": minimap.visible})
			minimap.visible = false
	elif category == "ui":
		for node: CanvasLayer in world.find_children("*", "CanvasLayer", true, false):
			saved.append({"node": node, "property": "visible", "value": node.visible})
			node.visible = false
	elif category == "shadows":
		for node: Light3D in world.find_children("*", "Light3D", true, false):
			saved.append({"node": node, "property": "shadow_enabled", "value": node.shadow_enabled})
			node.shadow_enabled = false
	else:
		for record: Dictionary in records:
			if record.category != category:
				continue
			var node: GeometryInstance3D = record.node as GeometryInstance3D
			saved.append({"node": node, "property": "layers", "value": node.layers})
			node.layers = 0
	return saved

func restore(saved: Array[Dictionary]) -> void:
	for entry: Dictionary in saved:
		(entry.node as Node).set(entry.property, entry.value)

func save_report() -> void:
	if OS.has_feature("web"):
		# Output is scoped to this diagnostic canvas; it contains no account data.
		JavaScriptBridge.eval("document.querySelector('canvas')?.setAttribute('data-render-probe'," + JSON.stringify(JSON.stringify(report)) + ")")
	else:
		FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))

func finish() -> void:
	report.status = "complete" if report.errors.is_empty() else "failed"
	save_report()
	if not OS.has_feature("web"):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://render_submission_probe.cfg"))
	print("SUBMISSION_DONE ", output, " errors=", report.errors)
	if is_instance_valid(world):
		world.process_mode = Node.PROCESS_MODE_DISABLED
	if not OS.has_feature("web"):
		tree.quit(0 if report.errors.is_empty() else 1)
