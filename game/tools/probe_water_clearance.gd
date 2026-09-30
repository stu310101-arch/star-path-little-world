extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world: Node3D=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	world.set_process(false)
	await physics_frame
	var player: PlanetPlayer=world.get("player") as PlanetPlayer
	var data: Dictionary=(JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array)[1]
	var ecology: RefCounted=(load("res://tools/ecology_world.gd") as Script).new() as RefCounted
	for x: int in range(-36,37,2):
		for y: int in range(-34,35,2):
			var p: Vector2=Vector2(x,y)
			if float(ecology.call("water_distance",p,data)) < -.8 and float(ecology.call("path_distance",p,data))>2.0 and float(ecology.call("edge_distance",p,data,1))>1.0:
				var normal: Vector3=PlanetGeometry.surface(Vector3.RIGHT,p,48).normalized()
				var hit: Dictionary=player.ground_at(normal)
				if not hit.is_empty():
					print("WATER_HIT "+str(p)+" "+str((hit.collider as Node).get_path())+" "+str(hit.position)+" water_distance="+str(ecology.call("water_distance",p,data))+" path_distance="+str(ecology.call("path_distance",p,data)))
	quit()
