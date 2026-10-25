extends SceneTree

## Vehicle inspection camera inside the unmodified production world. Uses its
## normal streaming, meshes, daylight, surfaces and all three authored traffic
## cars. Only pauses actors and moves the review camera after loading.
const Fixture = preload("res://tests/startup_fixture.gd")
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(1)
		return
	root.size = Vector2i(1440,900)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var hud: CanvasLayer = world.get("hud") as CanvasLayer
	var settings: Node = hud.get("graphics_settings") as Node
	settings.set("settings_path","user://vehicle_capture.cfg")
	settings.call("set_quality_profile","standard")
	settings.call("set_frame_limit",30)
	var deadline: int = Time.get_ticks_msec()+120000
	while not bool(world.get("startup_presented")) and Time.get_ticks_msec()<deadline:
		await process_frame
	world.call("teleport_to","counseling")
	if not await Fixture.wait_roaming(world,self,120000):
		quit(1)
		return
	var streaming: Node = world.get("streaming") as Node
	var traffic: Node3D
	deadline = Time.get_ticks_msec()+120000
	while Time.get_ticks_msec()<deadline:
		var region: Dictionary = (streaming.get("_regions") as Dictionary).get("counseling",{})
		if bool(region.get("ready",false)) and bool(region.get("active",false)):
			for chunk: Node3D in region.roots:
				traffic = chunk.find_child("CityTraffic",true,false) as Node3D
				if traffic!=null:
					break
		if traffic!=null:
			break
		await process_frame
	if traffic==null:
		push_error("Counseling production traffic failed to stream")
		quit(1)
		return
	# Roaming state becomes ready before the HUD's 100 ms refresh. Let the
	# production update dismiss its own preparation card before pausing it.
	deadline = Time.get_ticks_msec()+5000
	while (hud.get("preparation_overlay") as Control).visible and Time.get_ticks_msec()<deadline:
		await process_frame
	if (hud.get("preparation_overlay") as Control).visible:
		push_error("Preparation HUD did not finish its normal ready transition")
		quit(1)
		return
	hud.call("close_panel")
	world.set_process(false)
	traffic.set_process(false)
	(world.get("player") as Node).set_physics_process(false)
	var camera: Camera3D = world.get("camera") as Camera3D
	camera.fov = 48
	camera.near = .1
	var output: String = ProjectSettings.globalize_path("res://../deliverables/vehicles/world")
	DirAccess.make_dir_recursive_absolute(output)
	var evidence: Array[Dictionary] = []
	for child: Node in traffic.get_children():
		var car: Node3D = child as Node3D
		var label: String = str(car.get_meta("vehicle_model","legacy"))
		if label=="legacy":
			push_error("Stale baked mini car in production traffic")
			quit(1)
			return
		# Keep the lens above the actual lane so roadside trees do not hide the
		# model being inspected. Nothing in the world is hidden for this review.
		camera.global_position = car.global_transform*Vector3(2.7,2.4,7.0)
		camera.look_at(car.global_position+car.global_basis.y*.8,car.global_basis.y)
		for frame: int in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = output.path_join(label+"-street.png")
		root.get_texture().get_image().save_png(path)
		evidence.append({"model":label,"position":var_to_str(car.global_position),"scale":var_to_str(car.scale),"vehicle_length_m":car.get_meta("vehicle_length"),"image":path})
		print("VEHICLE_WORLD_CAPTURE ",label)
	var file: FileAccess = FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"source":"production world with a vehicle review camera","profile":"standard","renderer":RenderingServer.get_current_rendering_method(),"cars":evidence},"\t"))
	print("VEHICLE_WORLD_CAPTURE_COMPLETE")
	world.queue_free()
	await process_frame
	quit()
