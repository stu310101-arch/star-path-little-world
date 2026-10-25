extends SceneTree
const Orrery = preload("res://scripts/recommendation_orrery.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(label: String, value: bool) -> void:
	checks.append({"test":label,"passed":value})
	if not value:
		failures += 1
	print("ORRERY_CHECK ",label," ",value)

func tick() -> void:
	await create_timer(.25).timeout
	await process_frame

func validate_model(model: Node3D, label: String) -> void:
	root.add_child(model)
	var control: Node = Orrery.new()
	root.add_child(control)
	control.call("set_motion_enabled",true,false)
	control.call("configure",model,false)
	var outer: Node3D = model.find_child("OrreryOuterRing",true,false) as Node3D
	var inner: Node3D = model.find_child("OrreryInnerRing",true,false) as Node3D
	var orbit: Node3D = model.find_child("OrreryOrbit",true,false) as Node3D
	check(label+" exports three independent pivots",outer!=null and inner!=null and orbit!=null)
	if outer==null or inner==null or orbit==null:
		model.free()
		control.free()
		return
	var positions: Array[Vector3] = [outer.position,inner.position,orbit.position]
	var before: Array[Quaternion] = [outer.quaternion,inner.quaternion,orbit.quaternion]
	control.call("set_presentation_active",true)
	await tick()
	var after: Array[Quaternion] = [outer.quaternion,inner.quaternion,orbit.quaternion]
	check(label+" outer ring moves",before[0].angle_to(after[0])>.01)
	check(label+" inner ring moves independently",before[1].angle_to(after[1])>before[0].angle_to(after[0]))
	check(label+" orbit moves faster than rings",before[2].angle_to(after[2])>before[1].angle_to(after[1]))
	check(label+" instrument stays anchored",outer.position==positions[0] and inner.position==positions[1] and orbit.position==positions[2])
	control.call("set_motion_enabled",false,false)
	await tick()
	check(label+" pause freezes all parts",outer.quaternion.is_equal_approx(after[0]) and inner.quaternion.is_equal_approx(after[1]) and orbit.quaternion.is_equal_approx(after[2]))
	control.call("set_low_quality",true)
	control.call("set_motion_enabled",true,false)
	await tick()
	check(label+" low quality keeps main motion",not outer.quaternion.is_equal_approx(after[0]) and not orbit.quaternion.is_equal_approx(after[2]))
	check(label+" low quality freezes secondary ring",inner.quaternion.is_equal_approx(after[1]))
	control.call("set_presentation_active",false)
	var held: Quaternion = outer.quaternion
	await tick()
	check(label+" modal suspension stops motion",outer.quaternion.is_equal_approx(held))
	control.call("set_presentation_active",true)
	control.call("_notification",Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	await tick()
	check(label+" background suspension stops motion",outer.quaternion.is_equal_approx(held))
	control.call("_notification",Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await tick()
	check(label+" focus resumes without rebuilding",not outer.quaternion.is_equal_approx(held))
	control.set("browser_reduced_motion",true)
	control.call("_update_playback")
	held = outer.quaternion
	await tick()
	check(label+" reduced motion pauses clips",outer.quaternion.is_equal_approx(held))
	control.set("browser_reduced_motion",false)
	control.call("_update_playback")
	var player: AnimationPlayer = (control.get("players") as Dictionary)["OrreryOrbit"]
	player.seek(player.current_animation_length-.10,true)
	await tick()
	check(label+" clip loops continuously",player.current_animation_position<.5 and player.is_playing())
	control.free()
	model.free()
	await process_frame

func run() -> void:
	Engine.max_fps = 60
	var assets: bool = OS.get_cmdline_user_args().has("--assets")
	if assets:
		for path: String in ["res://assets/recommendation_room/recommendation_room.glb","res://generated/low/recommendation/recommendation_room.glb"]:
			var packed: PackedScene = load(path) as PackedScene
			check(path+" loads",packed!=null)
			if packed!=null:
				await validate_model(packed.instantiate() as Node3D,"low" if "/low/" in path else "full")
	else:
		var model: Node3D = Node3D.new()
		for name_value: String in ["OrreryOuterRing","OrreryInnerRing","OrreryOrbit"]:
			var part: Node3D = Node3D.new()
			part.name = name_value
			part.position = Vector3(.65,1.23,-3.83)
			part.rotation = Vector3(.4,.2,.1)
			model.add_child(part)
		await validate_model(model,"pivot fixture")
	var directory: String = ProjectSettings.globalize_path("res://../deliverables/recommendation-room")
	DirAccess.make_dir_recursive_absolute(directory)
	var report: FileAccess = FileAccess.open(directory.path_join("orrery-assets.json" if assets else "orrery-controller.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual AnimationPlayer playback; named model pivots" if assets else "Controller with synthetic pivots"},"\t"))
	print("ORRERY_DONE checks=",checks.size()," failures=",failures)
	quit(0 if failures==0 else 1)
