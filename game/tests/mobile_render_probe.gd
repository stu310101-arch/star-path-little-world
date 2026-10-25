extends SceneTree

const Startup = preload("res://tests/startup_fixture.gd")
var world: Node3D
var rows: Array[Dictionary] = []
var label: String = "baseline"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	root.size = Vector2i(960,600)
	var legacy_assets: bool=OS.get_cmdline_user_args().has("--legacy-assets")
	world = (load("res://../build/legacy-render/world.tscn" if legacy_assets else "res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	if legacy_assets:
		for region: Dictionary in (world.get("streaming") as Node).get("_regions").values():
			for chunk: Dictionary in region.chunks: chunk.path="res://../build/legacy-render/"+str(chunk.path).get_file()
	var settings: Node = world.get("graphics_settings") as Node
	settings.set("_mobile_web",true)
	settings.set("quality_profile","balanced")
	settings.set("msaa_enabled",false)
	settings.call("apply_settings")
	if OS.get_cmdline_user_args().has("--legacy-renderer"):
		# Same original meshes and shaders as the pre-change mobile renderer.
		# The new optional resources stay serialized but are never activated.
		world.call("_apply_mobile_quality")
		(world.get("streaming") as Node).call("set_low_quality",true)
	else: settings.emit_signal("state_changed")
	(world.get("hud") as CanvasLayer).visible = false
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await snapshot("overview")
	world.call("set_overview",false)
	await Startup.wait_roaming(world,self)
	for station: String in ["counseling","life","wordking"]:
		world.call("teleport_to",station)
		await Startup.wait_roaming(world,self)
		for _frame: int in range(90): await process_frame
		await snapshot(station)
	var output: String = "res://../deliverables/mobile-render/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	FileAccess.open(output+label+".json",FileAccess.WRITE).store_string(JSON.stringify({"label":label,"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"note":"Native Compatibility GPU counters at fixed camera poses, forced production mobile profile. Not an actual phone FPS benchmark.","rows":rows},"\t"))
	print("MOBILE_RENDER_PROBE ",JSON.stringify(rows))
	world.free()
	await process_frame
	quit()

func snapshot(pose: String) -> void:
	for _frame: int in range(30): await process_frame
	if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
	var totals: Dictionary = {"triangles":0,"surfaces":0,"meshes":0,"multi_instances":0}
	var big: Array[Dictionary] = []
	for node: Node in world.find_children("*","GeometryInstance3D",true,false):
		var visual: GeometryInstance3D = node as GeometryInstance3D
		if not visual.is_visible_in_tree() or visual.layers==0: continue
		var mesh: Mesh = null
		var instances: int = 1
		if visual is MeshInstance3D: mesh = (visual as MeshInstance3D).mesh
		elif visual is MultiMeshInstance3D and (visual as MultiMeshInstance3D).multimesh!=null:
			var multi: MultiMesh = (visual as MultiMeshInstance3D).multimesh
			mesh = multi.mesh
			instances = mini(multi.instance_count,multi.visible_instance_count) if multi.visible_instance_count>=0 else multi.instance_count
			totals.multi_instances+=instances
		if mesh==null: continue
		var triangles: int = 0
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
			triangles+=(indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())/3
		totals.triangles+=triangles*instances
		totals.surfaces+=mesh.get_surface_count()
		totals.meshes+=1
		big.append({"path":str(world.get_path_to(visual)),"triangles":triangles*instances,"surfaces":mesh.get_surface_count(),"instances":instances})
	big.sort_custom(func(a: Dictionary,b: Dictionary)->bool: return int(a.triangles)>int(b.triangles))
	var row: Dictionary = {"pose":pose,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"scene_visible_geometry":totals,"largest_visible":big.slice(0,18),"render_buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"static_memory_bytes":Performance.get_monitor(Performance.MEMORY_STATIC)}
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	var camera: Camera3D = root.get_camera_3d()
	row["avatar_scale"] = player.avatar_scale
	if camera!=null:
		row["camera_distance_to_player_m"] = camera.global_position.distance_to(player.global_position)
		row["camera_near_m"] = camera.near
		row["camera_far_m"] = camera.far
	var streamer: Node = world.get("streaming") as Node
	if streamer!=null: row["streaming"]=streamer.call("metrics")
	rows.append(row)
	if DisplayServer.get_name()!="headless":
		var output: String = "res://../deliverables/mobile-render/"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
		root.get_texture().get_image().save_png(output+label+"-"+pose+".png")
