extends Node3D

const Geo = preload("res://scripts/planet_geometry.gd")
var elapsed: float = 0.0
var quality_update_interval: float = 0.0
var _quality_accumulator: float = 0.0
var radius: float = 36.0
var route: PackedVector2Array = PackedVector2Array()
var distances: PackedFloat32Array = PackedFloat32Array()
var route_length: float = 0.0

func _ready() -> void:
	radius = float(get_meta("radius",36.0))
	var vertices: PackedVector2Array = get_meta("route_points",PackedVector2Array([Vector2(-14,-15),Vector2(14,-15),Vector2(14,15),Vector2(-14,15)])) as PackedVector2Array
	# Rounded lane follows this district's actual road polygon.
	for i: int in range(vertices.size()):
		var p: Vector2 = vertices[i]
		var before: Vector2 = (p-vertices[(i-1+vertices.size())%vertices.size()]).normalized()
		var after: Vector2 = (vertices[(i+1)%vertices.size()]-p).normalized()
		var inset: Vector2 = (Vector2(-before.y,before.x)+Vector2(-after.y,after.x)).normalized()*.8
		var a: Vector2 = p-before*1.7+inset
		var b: Vector2 = p+after*1.7+inset
		for j: int in range(10):
			var t: float = float(j)/10.0
			route.append(a.lerp(p+inset,t).lerp((p+inset).lerp(b,t),t))
	distances.append(0.0)
	for i: int in range(route.size()):
		route_length += route[i].distance_to(route[(i+1)%route.size()])
		distances.append(route_length)
	update_traffic(0.0)

func sample_route(distance: float) -> Vector2:
	var d: float = fposmod(distance,route_length)
	for i: int in range(route.size()):
		if d <= distances[i+1]:
			return route[i].lerp(route[(i+1)%route.size()],(d-distances[i])/maxf(.001,distances[i+1]-distances[i]))
	return route[0]

func _process(delta: float) -> void:
	elapsed += delta
	_quality_accumulator += delta
	if _quality_accumulator < quality_update_interval:
		return
	update_traffic(_quality_accumulator)
	_quality_accumulator = 0.0

func update_traffic(delta: float) -> void:
	if route.is_empty():
		return
	var player: Node3D = get_tree().current_scene.get_node_or_null("Player") as Node3D if get_tree().current_scene != null else null
	for child: Node in get_children():
		var car: Node3D = child as Node3D
		var up: Vector3 = car.get_meta("district_up") as Vector3
		var progress: float = float(car.get_meta("progress",0.0))
		var next: Vector2 = sample_route(progress+2.0)
		var ahead: Vector3 = Geo.surface(up,next,radius+.40)
		var blocked: bool = player != null and player.position.distance_to(ahead)<1.75
		for other: Node in get_children():
			if other == car:
				continue
			var gap: float = fposmod(float(other.get_meta("progress",0.0))-progress,route_length)
			blocked = blocked or (gap>0.0 and gap<4.2)
		if not blocked:
			progress += delta*float(car.get_meta("speed",1.6))
			for wheel: Node in car.find_children("wheel-*","Node3D",true,false):
				if str(wheel.name) != "wheel-back":
					(wheel as Node3D).rotate_x(delta*float(car.get_meta("speed",1.6))/.29)
		car.set_meta("progress",progress)
		var p: Vector2 = sample_route(progress)
		var n: Vector3 = Geo.surface(up,p,radius).normalized()
		var forward: Vector3 = (Geo.surface(up,sample_route(progress+.15),radius)-n*radius).slide(n).normalized()
		car.transform = Transform3D(Basis(n.cross(forward).normalized(),n,forward),n*(radius+.30))
