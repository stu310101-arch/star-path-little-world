extends SceneTree
const Geo=preload("res://scripts/planet_geometry.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var world: Node3D=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	await physics_frame
	await physics_frame
	var a: Vector3=Geo.surface(Vector3.RIGHT,Vector2(7,26),48).normalized()
	var b: Vector3=Geo.surface(Vector3.RIGHT,Vector2(0,26),48).normalized()
	var normal: Vector3=(b*48+a.cross(b).normalized()*.325).normalized()
	var axes: Basis=Geo.frame(normal)
	var space: PhysicsDirectSpaceState3D=world.get_world_3d().direct_space_state
	assert(not Geo.ground_probe(space,normal,48).is_empty(),"Shared-edge floor query must recover the real floor")
	print("CONSERVATIVE_GROUND_QUERY_OK")
	for shift: Vector2 in [Vector2.ZERO,Vector2(.001,0),Vector2(-.001,0),Vector2(0,.001),Vector2(0,-.001),Vector2(.02,0),Vector2(-.02,0)]:
		var n: Vector3=(normal*48+axes.x*shift.x+axes.z*shift.y).normalized()
		var hit: Dictionary=space.intersect_ray(PhysicsRayQueryParameters3D.create(n*50,n*47.65,1))
		print("JOIN_PROBE ",shift," normal=",n," hit=", "EMPTY" if hit.is_empty() else str((hit.collider as Node).get_path()))
	quit()
