extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Landforms = preload("res://tools/world_landforms.gd")
const PlayerScript = preload("res://scripts/planet_player.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for action: String in ["jump","move_left","move_right","move_forward","move_back","run"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var radius: float = float(layout.radius)
	var globe: Node3D = (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(globe)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = globe.get_world_3d().direct_space_state
	var roots: Array[Dictionary] = []
	for body: StaticBody3D in globe.find_children("*","StaticBody3D",true,false):
		if not body.has_meta("planting_group"):
			continue
		var ground: Dictionary = Geo.ground_probe(space,body.global_position.normalized(),radius)
		var gap: float = body.global_position.length()-(ground.position as Vector3).length() if not ground.is_empty() else INF
		roots.append({"group":body.get_meta("planting_group"),"species":body.get_meta("species"),"district":body.get_meta("district_index"),"root_gap_m":gap})
		if ground.is_empty() or gap>.06 or gap<-.04:
			failures.append("Tree root contact "+str(body.get_meta("planting_group"))+" gap="+str(gap))
	var drops: Array[Dictionary] = []
	var player: PlanetPlayer = PlayerScript.new() as PlanetPlayer
	player.planet_radius = radius
	globe.add_child(player)
	player.controls_enabled = false
	player.set_physics_process(false)
	for index: int in range(districts.size()):
		var data: Dictionary = districts[index]
		var values: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(values[0],values[1],values[2])
		var field: RefCounted = Landforms.new()
		field.call("configure",data,index,radius,up)
		var selected: Vector3 = Vector3.ZERO
		var selected_height: float = -INF
		var ridge: Array = Biomes.spec(str(data.station)).ridges[0]
		var centre: Vector2=Vector2((ridge[0]+ridge[2])*.5,(ridge[1]+ridge[3])*.5)
		for x: int in range(-4,5):
			for z: int in range(-4,5):
				var p: Vector2 = centre+Vector2(float(x)*2.0,float(z)*2.0)
				if float(field.call("dry_distance",p))<1.0:
					continue
				var n: Vector3 = Geo.surface(up,p,radius).normalized()
				var hit: Dictionary = Geo.ground_probe(space,n,radius)
				if hit.is_empty():
					continue
				var ground: Vector3 = hit.position as Vector3
				# This regression drops onto bare terrain. A lower rock ledge can
				# sit above the capsule-at-ground query while still intercepting a
				# falling character, so reject obstructed vertical drop columns too.
				var drop_column: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(n*(radius+50.0),ground+n*.02,8)
				if not space.intersect_ray(drop_column).is_empty(): continue
				var capsule: CapsuleShape3D = CapsuleShape3D.new()
				capsule.height=1.6
				capsule.radius=.30
				var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
				query.shape=capsule
				query.collision_mask=8
				query.transform=Transform3D(Geo.frame(n),ground+n*.84)
				if not space.intersect_shape(query,1).is_empty():
					continue
				if ground.length()-radius>selected_height:
					selected=ground
					selected_height=ground.length()-radius
		if selected==Vector3.ZERO:
			failures.append(str(data.station)+": no clear ridge drop target")
			continue
		player.teleport(selected.normalized(),selected.length()+1.8)
		player.set_physics_process(true)
		var landed: bool = false
		for _frame: int in range(120):
			await physics_frame
			if player.is_on_floor() and not player.needs_settle:
				landed=true
				break
		player.set_physics_process(false)
		var support: Dictionary = player.ground_at(player.global_position.normalized())
		var gap: float = player.global_position.length()-(support.position as Vector3).length() if not support.is_empty() else -INF
		var passed: bool = landed and gap>=-.035 and gap<.15
		drops.append({"station":data.station,"ridge_height_m":selected_height,"landed":landed,"feet_gap_m":gap,"passed":passed})
		if not passed:
			failures.append(str(data.station)+": real player failed to land on generated ridge")
		print("LANDFORM_PLAYER_DROP ",data.station," landed=",landed," gap=",gap)
	var report: Dictionary = {"passed":failures.is_empty(),"failures":failures,"trees":roots,"player_drops":drops,
		"scope":"All authored solid tree roots against actual generated collider; production PlanetPlayer capsule/gravity drops on each district's raised ridge. Avatar rendering/animations are not loaded by this physics-only test."}
	var output: String = ProjectSettings.globalize_path("res://../deliverables/world-redesign/landform-grounding-checks.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LANDFORM_GROUNDING trees=",roots.size()," drops=",drops.size()," failures=",failures.size())
	for failure: String in failures:
		push_error(failure)
	globe.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
