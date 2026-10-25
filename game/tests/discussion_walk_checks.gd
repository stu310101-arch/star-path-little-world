extends SceneTree
## Fixture-only direct entry; shipped login entry and account gate are unchanged.
const Garden = preload("res://scripts/discussion_garden.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const OUTPUT: String = "res://../deliverables/discussion-garden/qa/"
class Quality:
	extends Node
	signal state_changed
	func is_low_quality() -> bool:
		return false
class Account:
	extends Node
	signal forum_message(packet: Dictionary)
	signal closed
	signal state_changed(user: Dictionary)
	var user: Dictionary = {"profileReady":true,"sessionGeneration":7}
	func request_forum_page(_command: Dictionary) -> bool:
		return false
	func open_view(_view: String) -> bool:
		return false
var room: Node3D
var player: CharacterBody3D
var camera: Camera3D
var checks: Array[Dictionary] = []
var captures: Array[String] = []
var failures: int = 0
var travelled: float = 0
var overlap_count: int = 0
var first_overlap: Dictionary = {}
var query := PhysicsShapeQueryParameters3D.new()
var capture_enabled: bool = false
func _initialize() -> void:
	run.call_deferred()
func check(title: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":title,"passed":passed,"evidence":evidence})
	print("GARDEN_WALK_CHECK ",title," ",passed)
	if not passed:
		failures += 1
func tick() -> void:
	var before: Vector3 = player.position
	await physics_frame
	await process_frame
	travelled += before.distance_to(player.position)
	query.transform = Transform3D(Basis.IDENTITY,camera.global_position)
	var hits: Array[Dictionary] = room.get_world_3d().direct_space_state.intersect_shape(query,1)
	if not hits.is_empty():
		overlap_count += 1
		if first_overlap.is_empty():
			first_overlap = {"player":player.position,"camera":camera.position,"body":str(hits[0].collider.get_path())}
func walk_to(target: Vector3, label: String) -> bool:
	if OS.get_cmdline_user_args().has("--snapshots-only"):
		var facing: Vector3 = (target-player.position).slide(Vector3.UP).normalized()
		if facing.length_squared()<.5:
			facing = Vector3.FORWARD
		player.call("place_at",target,facing)
		room.call("_update_zone_visibility",true)
		room.set("camera_yaw",atan2(-facing.x,-facing.z))
		room.call("update_camera",0,true)
		for frame: int in range(4):
			await tick()
		return true
	var arrived: bool = false
	player.set("allow_test_input",true)
	player.set("test_running",true)
	var max_frames: int = int(player.position.distance_to(target)/float(player.get("run_speed"))*90)+300
	for frame: int in range(max_frames):
		var remaining: Vector3 = (target-player.position).slide(Vector3.UP)
		if remaining.length()<.3:
			arrived = true
			break
		var direction: Vector3 = remaining.normalized()
		player.set("heading",direction)
		player.set("test_direction",Vector2(0,-1))
		room.set("camera_yaw",lerp_angle(float(room.get("camera_yaw")),atan2(-direction.x,-direction.z),.12))
		await tick()
	player.set("test_direction",Vector2.ZERO)
	player.set("allow_test_input",false)
	for frame: int in range(5):
		await tick()
	var blockers: Array[String] = []
	for index: int in range(player.get_slide_collision_count()):
		var collision: KinematicCollision3D = player.get_slide_collision(index)
		if absf(collision.get_normal().y)<.7:
			blockers.append(str((collision.get_collider() as Node).get_path()))
	check("Continuous movement reaches "+label,arrived,{"position":player.position,"target":target,"blockers":blockers})
	return arrived
func capture(label: String) -> void:
	if not capture_enabled:
		return
	# Let Label/Control redraw notifications catch up before the explicit draw.
	await process_frame
	RenderingServer.force_draw(false)
	var path: String = ProjectSettings.globalize_path(OUTPUT+label+".png")
	check("Renderer capture "+label,root.get_texture().get_image().save_png(path)==OK)
	captures.append(path)

func inspect_forest_devices(zone: Dictionary, hub: Vector3) -> void:
	var path: Array[Vector3] = [hub]
	for point: Variant in zone.get("walk_path",[zone.controls.point]):
		path.append(Garden.vector(point))
	var devices: Array = (room.get("zones") as Dictionary).high_school.devices
	# The published approach route stops at the entrance control point; the
	# woodland's authored straight central path continues between both cabins.
	var entrance: Vector3 = Garden.vector(zone.controls.point)
	var inward: Vector3 = (Garden.vector(zone.center)-entrance).slide(Vector3.UP).normalized()
	var farthest: float = 0
	for device: Node3D in devices:
		farthest = maxf(farthest,(device.position-entrance).dot(inward))
	path.append(entrance+inward*(farthest+1))
	for index: int in range(devices.size()):
		var device: Node3D = devices[index]
		var path_point: Vector3 = path[0]
		var distance: float = INF
		for segment: int in range(path.size()-1):
			var nearest_point: Vector3 = Geometry3D.get_closest_point_to_segment(device.position,path[segment],path[segment+1])
			var separation: float = nearest_point.distance_squared_to(device.position)
			if separation<distance:
				distance = separation
				path_point = nearest_point
		var toward_path: Vector3 = (path_point-device.position).slide(Vector3.UP).normalized()
		var front: Vector3 = device.global_basis.z.normalized()
		check("Forest device %d faces the center path" % index,front.dot(toward_path)>.01,{"dot":front.dot(toward_path),"position":device.position})
		var outside: bool = true
		for footprint: Dictionary in zone.get("indoor_footprints",[]):
			var relative: Vector3 = (device.position-Garden.vector(footprint.center)).rotated(Vector3.UP,-float(footprint.get("rotation_y",0)))
			var half: Vector3 = Garden.vector(footprint.size)*.5
			if absf(relative.x)<half.x and absf(relative.z)<half.z:
				outside = false
		if zone.has("indoor_footprints"):
			check("Forest device %d remains outside every cabin" % index,outside)
		if not await walk_to(path_point,"forest device %d path" % index):
			continue
		if not await walk_to(device.position+front*1.1,"forest device %d front" % index):
			continue
		room.call("refresh_nearest")
		var nearest: Dictionary = room.get("nearest")
		check("Forest front approach selects device %d" % index,nearest.get("zone")=="high_school" and nearest.get("slot")==index)
		var toward_device: Vector3 = -front
		var yaw: float = atan2(-toward_device.x,-toward_device.z)
		for offset: float in [0.0,PI/4,-PI/4]:
			room.set("camera_yaw",yaw+offset)
			room.set("camera_distance",3.1)
			room.set("camera_pitch",.23)
			room.call("update_camera",0,true)
			await tick()
		if index in [0,7]:
			await capture("04-high-school-device-%d-front-side" % index)
		await walk_to(path_point,"forest device %d back to path" % index)
	room.set("camera_distance",4.5)
	await walk_to(Garden.vector(zone.controls.point),"forest control point")

func inspect_spoke_widths(layout: Dictionary, hub: Vector3) -> void:
	for zone: Dictionary in layout.zones:
		var direction: Vector3 = (Garden.vector(zone.controls.point)-hub).slide(Vector3.UP).normalized()
		var sideways: Vector3 = direction.cross(Vector3.UP)
		var route: Array = zone.get("walk_path",[zone.controls.point])
		for offset: float in [-1.35,0.0,1.35]:
			var lane_name: String = "%s spoke lane %.2fm" % [zone.id,offset]
			await walk_to(hub+sideways*offset,lane_name+" hub start")
			for index: int in range(route.size()):
				if not await walk_to(Garden.vector(route[index])+sideways*offset,lane_name+" point "+str(index)):
					break
			for index: int in range(route.size()-2,-1,-1):
				if not await walk_to(Garden.vector(route[index])+sideways*offset,lane_name+" return "+str(index)):
					break
			await walk_to(hub,lane_name+" hub return")

func inspect_ring_walkways(layout: Dictionary, hub: Vector3) -> void:
	var navigation: Dictionary = layout.get("navigation",{})
	var ring: Array = navigation.get("ring_points",[])
	check("Compact garden has a connected open ring to explore",ring.size()>20 and not bool(navigation.get("ring_closed",true)))
	if ring.is_empty():
		return
	var grounded: bool = true
	# Walk the actual CharacterBody across the center and both usable margins.
	# Reverse alternate passes so the transition itself is also traversed.
	for lane: int in range(3):
		var offset: float = [-1.25,0.0,1.25][lane]
		var indices: Array[int] = []
		for index: int in range(ring.size()):
			indices.append(index)
		if lane%2==1:
			indices.reverse()
		for index: int in indices:
			var point: Vector3 = Garden.vector(ring[index])
			var sideways: Vector3 = (point-hub).slide(Vector3.UP).normalized()
			if not await walk_to(point+sideways*offset,"ring lane %.2fm point %d" % [offset,index]):
				return
			grounded = grounded and player.is_on_floor() and player.position.y > -.1
			if lane==1:
				for spoke: Dictionary in navigation.get("spokes",[]):
					if int(spoke.ring_index)!=index:
						continue
					if not await walk_to(Garden.vector(spoke.entry),str(spoke.zone_id)+" ring-to-area junction"):
						return
					if not await walk_to(point,str(spoke.zone_id)+" area-to-ring junction"):
						return
					grounded = grounded and player.is_on_floor()
	check("Ring and all five junctions retain continuous ground support",grounded)
	await walk_to(hub,"ring route return to central plaza")

func capture_lighting_probe() -> void:
	var environment: Environment = (room.find_children("*","WorldEnvironment",true,false)[0] as WorldEnvironment).environment
	var sun: DirectionalLight3D = room.get_node("GardenSun")
	var seen: Dictionary = {}
	for instance: MeshInstance3D in (room.get("room_model") as Node3D).find_children("*","MeshInstance3D",true,false):
		for index: int in range(instance.mesh.get_surface_count()):
			var mat: Material = instance.get_active_material(index)
			if mat is StandardMaterial3D and mat.resource_name in ["MAT_Garden_sand","MAT_Garden_oak"] and not seen.has(mat.resource_name):
				seen[mat.resource_name] = true
				print("LIGHT_MATERIAL ",mat.resource_name," albedo=",mat.albedo_color," emission=",mat.emission_enabled," shade=",mat.shading_mode," roughness=",mat.roughness," specular=",mat.metallic_specular)
	for preset: Dictionary in [{"name":"current","ambient":.26,"sun":.45,"tonemap":Environment.TONE_MAPPER_FILMIC},{"name":"linear","ambient":.26,"sun":.45,"tonemap":Environment.TONE_MAPPER_LINEAR},{"name":"neutral","ambient":.15,"sun":.20,"tonemap":Environment.TONE_MAPPER_LINEAR},{"name":"ambient","ambient":.26,"sun":0.0,"tonemap":Environment.TONE_MAPPER_LINEAR},{"name":"direct","ambient":0.0,"sun":.45,"tonemap":Environment.TONE_MAPPER_LINEAR}]:
		environment.ambient_light_energy = preset.ambient
		environment.tonemap_mode = preset.tonemap
		sun.light_energy = preset.sun
		await capture("lighting-"+preset.name)

func capture_performance_probe() -> void:
	# Exactly one real render per 30 Hz process frame, including while Codex
	# covers the window; an occluded window must not fake a cheap GPU sample.
	Engine.max_fps = 30
	RenderingServer.set_render_loop_enabled(false)
	for warmup: int in range(30):
		await process_frame
		RenderingServer.force_draw(false)
	var frames: Array[float] = []
	var draws: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	var started: int = previous
	var max_draw_calls: int = 0
	var max_primitives: int = 0
	while Time.get_ticks_usec()-started<10000000:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		previous = now
		RenderingServer.force_draw(false)
		draws.append(float(Time.get_ticks_usec()-now)/1000.0)
		max_draw_calls = maxi(max_draw_calls,int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		max_primitives = maxi(max_primitives,int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	var elapsed: float = float(Time.get_ticks_usec()-started)/1000000.0
	frames.sort()
	draws.sort()
	var report: Dictionary = {"scene":"discussion_garden","point":"high_school entrance, both cabins and background trees","duration_seconds":elapsed,"rendered_frames":frames.size(),"measured_fps":float(frames.size())/elapsed,"frame_limit":30,"viewport":"1440x900","quality":"standard, directional shadows on","renderer":RenderingServer.get_current_rendering_method(),"adapter":RenderingServer.get_video_adapter_name(),"render_mode":"one forced native render per process frame; automatic draw disabled to avoid occlusion or duplicate frames","frame_ms_p50":frames[frames.size()/2],"frame_ms_p95":frames[int(frames.size()*.95)],"frame_ms_max":frames.back(),"draw_submit_ms_p95":draws[int(draws.size()*.95)],"max_draw_calls":max_draw_calls,"max_primitives":max_primitives,"garden_sha256":FileAccess.get_sha256("res://assets/discussion_garden/garden.glb")}
	var file := FileAccess.open(OUTPUT+"performance-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("GARDEN_PERFORMANCE ",JSON.stringify(report))
	RenderingServer.set_render_loop_enabled(true)
func run() -> void:
	capture_enabled = OS.get_cmdline_user_args().has("--capture")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440,900)
	var account := Account.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var quality := Quality.new()
	root.add_child(quality)
	room = Garden.new()
	room.set("graphics_settings",quality)
	root.add_child(room)
	current_scene = room
	check("Authored garden and avatar become ready",await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	player = room.get("player")
	camera = room.get("camera")
	var sphere := SphereShape3D.new()
	sphere.radius = .17
	query.shape = sphere
	query.collision_mask = 257
	query.exclude = [player.get_rid()]
	for frame: int in range(8):
		await tick()
	var layout: Dictionary = room.get("layout")
	var hub: Vector3 = Garden.vector(layout.get("hub",[0,.06,0]))
	if OS.get_cmdline_user_args().has("--forest-only"):
		for zone: Dictionary in layout.zones:
			if zone.id=="high_school":
				var facing: Vector3 = (Garden.vector(zone.center)-Garden.vector(zone.controls.point)).normalized()
				player.call("place_at",Garden.vector(zone.controls.point),facing)
				room.call("_update_zone_visibility",true)
				room.set("camera_yaw",atan2(-facing.x,-facing.z))
				room.call("update_camera",0,true)
				await tick()
				room.call("refresh_nearest")
				check("Forest entrance resolves matching topic",str(room.get("current_zone"))=="high_school")
				if OS.get_cmdline_user_args().has("--lighting-probe"):
					await capture_lighting_probe()
					room.queue_free()
					quit()
					return
				if OS.get_cmdline_user_args().has("--performance"):
					await capture_performance_probe()
					room.queue_free()
					quit()
					return
				await capture("04-high_school-walk")
				await inspect_forest_devices(zone,hub)
		check("Forest camera lens avoids authored collision proxies",overlap_count==0,{"count":overlap_count,"first":first_overlap})
		finish_report(layout,"forest-visual-report.json" if OS.get_cmdline_user_args().has("--snapshots-only") else "forest-report.json")
		return
	check("Spawn settles on authored ground",player.is_on_floor())
	await capture("00-spawn")
	if OS.get_cmdline_user_args().has("--spokes"):
		var welcome: Node3D = room.get_node_or_null("WelcomeSignCamera")
		check("Welcome sign and lintel have camera-only blockers",welcome!=null and room.get_node_or_null("WelcomeLintelCamera")!=null and (welcome as CollisionObject3D).collision_layer==256)
		if welcome!=null:
			await walk_to(Vector3(welcome.position.x,.06,welcome.position.z),"welcome gateway")
			for yaw: float in [0.0,PI/2,PI]:
				for pitch: float in [.28,.55,.75]:
					room.set("camera_yaw",yaw)
					room.set("camera_pitch",pitch)
					room.call("update_camera",0,true)
					await tick()
			room.set("camera_pitch",.28)
	await walk_to(hub,"central hub")
	if OS.get_cmdline_user_args().has("--spokes"):
		await inspect_spoke_widths(layout,hub)
	if OS.get_cmdline_user_args().has("--ring"):
		await inspect_ring_walkways(layout,hub)
	var zone_number: int = 0
	for zone: Dictionary in layout.zones:
		zone_number += 1
		var route: Array = zone.get("walk_path",[zone.controls.point])
		var path_success: bool = true
		for index: int in range(route.size()):
			if not await walk_to(Garden.vector(route[index]),str(zone.id)+" approach "+str(index)):
				path_success = false
				break
		room.call("refresh_nearest")
		check(str(zone.id)+" resolves matching topic",str(room.get("current_zone"))==str(zone.id))
		await capture("%02d-%s-walk" % [zone_number,zone.id])
		if zone.id=="high_school":
			await inspect_forest_devices(zone,hub)
		if capture_enabled:
			# Context view, then restore the real camera before continuing physics.
			var before: Transform3D = camera.global_transform
			var center: Vector3 = Garden.vector(zone.center)
			room.set_process(false)
			(room.get("hud") as CanvasLayer).hide()
			camera.position = center+Vector3(14,10,17)
			camera.look_at(center+Vector3.UP*1.5)
			await capture("%02d-%s-context" % [zone_number,zone.id])
			camera.global_transform = before
			(room.get("hud") as CanvasLayer).show()
			room.set_process(true)
		if path_success:
			for index: int in range(route.size()-2,-1,-1):
				if not await walk_to(Garden.vector(route[index]),str(zone.id)+" return "+str(index)):
					break
		if not await walk_to(hub,str(zone.id)+" back to hub"):
			# Continue diagnostics for the remaining zones after recording failure.
			player.call("place_at",hub)
			await tick()
	check("Camera lens avoids authored collision proxies",overlap_count==0,{"count":overlap_count,"first":first_overlap})
	check("Player remains grounded after five-zone route",player.is_on_floor())
	if capture_enabled:
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.size = Vector2i(390,844)
		for frame: int in range(5):
			await process_frame
		room.call("_resize_hud")
		await process_frame
		await capture("06-mobile-portrait")
		var viewport_rect: Rect2 = root.get_visible_rect()
		var controls_fit: bool = true
		for button: Node in (room.get("ui_root") as Control).find_children("*","Button",true,false):
			if (button as Button).is_visible_in_tree() and not viewport_rect.encloses((button as Button).get_global_rect()):
				controls_fit = false
		check("Portrait HUD controls remain within viewport",controls_fit)
	finish_report(layout,"visual-report.json" if OS.get_cmdline_user_args().has("--snapshots-only") else "walk-report.json")

func finish_report(layout: Dictionary, filename: String) -> void:
	var report: Dictionary = {"checks":checks,"failures":failures,"travelled_m":travelled,"captures":captures,"layout_revision":layout.get("revision",""),"layout_sha256":FileAccess.get_sha256(Garden.LAYOUT),"garden_sha256":FileAccess.get_sha256("res://assets/discussion_garden/garden.glb"),"movement_mode":"visual sampling only" if OS.get_cmdline_user_args().has("--snapshots-only") else "continuous CharacterBody3D physics at fixed 60 Hz","camera_overlap_count":overlap_count}
	var file := FileAccess.open(OUTPUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("GARDEN_WALK_RESULT failures=",failures," distance_m=",travelled)
	room.queue_free()
	quit(0 if failures==0 else 1)
