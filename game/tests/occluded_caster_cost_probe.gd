extends SceneTree

## Isolate renderer cost of retained shadow-only instances when all lights have
## shadows disabled. Temporary instance-layer edits only; no product changes.
const Fixture=preload("res://tests/startup_fixture.gd")
const OUTPUT="res://../deliverables/render-budget/caster-cost-isolation"
var world: Node3D
var settings: Node
var report: Dictionary={"method":"Same-process native Compatibility A/B/A/B/A; fixed water0 camera, world simulation paused; not Web/mobile hardware performance.","profiles":[],"scene_light_inventory":[],"errors":[]}

func _initialize() -> void: call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(1)
		return
	root.size=Vector2i(1280,800)
	root.gui_disable_input=true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	report.gpu=RenderingServer.get_video_adapter_name()
	report.renderer=RenderingServer.get_current_rendering_method()
	audit_scene_lights()
	world=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene=world
	settings=world.get("graphics_settings") as Node
	settings.set("settings_path","user://caster_cost_probe.cfg")
	for profile: String in ["low","mobile"]:
		world.process_mode=Node.PROCESS_MODE_INHERIT
		settings.set("_mobile_web",profile=="mobile")
		settings.call("set_quality_profile",profile)
		settings.call("set_frame_limit",90)
		Engine.max_fps=0
		world.call("setup_water_review",0,false)
		if not await Fixture.wait_roaming(world,self):
			report.errors.append("roaming preparation failed: "+profile)
			break
		await create_timer(2.0).timeout
		world.process_mode=Node.PROCESS_MODE_DISABLED
		Engine.max_fps=0
		var lights: Array[Dictionary]=[]
		var has_shadows: bool=false
		for light: Light3D in world.find_children("*","Light3D",true,false):
			lights.append({"path":str(world.get_path_to(light)),"visible":light.is_visible_in_tree(),"shadows":light.shadow_enabled})
			has_shadows=has_shadows or (light.is_visible_in_tree() and light.shadow_enabled)
		if has_shadows:
			report.errors.append("Cannot isolate no-shadow case with active shadow light")
			break
		var candidates: Array[Dictionary]=[]
		for visual: MeshInstance3D in world.find_children("*","MeshInstance3D",true,false):
			if visual.is_visible_in_tree() and visual.layers!=0 and visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:
				candidates.append({"node":visual,"layers":visual.layers})
		var row: Dictionary={"profile":profile,"mobile_policy":profile=="mobile","lights":lights,"retained_shadow_only_candidates":candidates.size(),"camera_transform":str((world.get("camera") as Camera3D).global_transform),"phases":[]}
		for phase: String in ["A0","B0","A1","B1","A2"]:
			var disabled: bool=phase.begins_with("B")
			for candidate: Dictionary in candidates:
				(candidate.node as MeshInstance3D).layers=0 if disabled else int(candidate.layers)
			await create_timer(.4).timeout
			var result: Dictionary=await sample(phase)
			(row.phases as Array).append(result)
			print("CASTER_COST ",profile," ",phase," candidates=",candidates.size()," gpu=",result.gpu_median_ms," cpu=",result.render_cpu_median_ms," frame=",result.median_ms," draws=",result.draw_calls," primitives=",result.primitives)
		for candidate: Dictionary in candidates: (candidate.node as MeshInstance3D).layers=int(candidate.layers)
		row.graphics=settings.call("get_state")
		row.streaming=world.get("streaming").call("metrics")
		report.profiles.append(row)
		save_report()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://caster_cost_probe.cfg"))
	current_scene=null
	world.queue_free()
	await process_frame
	await process_frame
	save_report()
	print("CASTER_COST_DONE errors=",report.errors)
	quit(0 if report.errors.is_empty() else 1)

func sample(phase: String) -> Dictionary:
	var frames: Array[float]=[]
	var gpu: Array[float]=[]
	var cpu: Array[float]=[]
	var draws: Array[int]=[]
	var primitives: Array[int]=[]
	var deadline: int=Time.get_ticks_msec()+2000
	var previous: int=Time.get_ticks_usec()
	while Time.get_ticks_msec()<deadline:
		await process_frame
		var now: int=Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		previous=now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	frames.sort();gpu.sort();cpu.sort();draws.sort();primitives.sort()
	return {"phase":phase,"layers_zero":phase.begins_with("B"),"frames":frames.size(),"median_ms":frames[frames.size()/2],"p95_ms":frames[mini(frames.size()-1,ceili(frames.size()*.95)-1)],"gpu_median_ms":gpu[gpu.size()/2],"render_cpu_median_ms":cpu[cpu.size()/2],"draw_calls":draws[draws.size()/2],"primitives":primitives[primitives.size()/2],"engine_frame_cap":Engine.max_fps}

func audit_scene_lights() -> void:
	var paths: Array[String]=["res://scenes/world.tscn"]
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	for region: Dictionary in catalog.districts:
		for chunk: Dictionary in region.chunks: paths.append(str(chunk.path))
	for path: String in paths:
		var scene: Node=(load(path) as PackedScene).instantiate()
		for light: Light3D in scene.find_children("*","Light3D",true,false):
			report.scene_light_inventory.append({"scene":path,"path":str(scene.get_path_to(light)),"type":light.get_class(),"shadow_enabled_authored":light.shadow_enabled})
		scene.free()
	report.audited_scene_count=paths.size()

func save_report() -> void:
	var folder: String=ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("report.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
