extends Node3D

const Geo = preload("res://scripts/planet_geometry.gd")
var elapsed: float = 0.0
var quality_update_interval: float = 0.0
var _quality_accumulator: float = 0.0
var swimmers: Array[Node3D] = []

func _ready() -> void:
	for child: Node in get_children():
		if child.has_meta("swim_path"):
			swimmers.append(child as Node3D)
	update_life(0.0)

func _process(delta: float) -> void:
	elapsed += delta
	_quality_accumulator += delta
	if _quality_accumulator < quality_update_interval:
		return
	update_life(elapsed)
	_quality_accumulator = 0.0

func update_life(time: float) -> void:
	var up: Vector3 = get_meta("district_up",Vector3.UP)
	var radius: float = float(get_meta("radius",48.0))
	for fish: Node3D in swimmers:
		var path: Dictionary = fish.get_meta("swim_path")
		var phase: float = float(fish.get_meta("phase",0.0))
		var t: float = time*float(path.get("speed",.25))+phase
		var center: Vector2 = Vector2(path.center[0],path.center[1])
		var a: Vector2 = Vector2(path.axes[0][0],path.axes[0][1])
		var b: Vector2 = Vector2(path.axes[1][0],path.axes[1][1])
		var p: Vector2 = center+a*cos(t)+b*sin(t)
		var tangent: Vector2 = -a*sin(t)+b*cos(t)
		var n: Vector3 = Geo.surface(up,p,radius).normalized()
		var district_frame: Basis = Geo.frame(up)
		var forward: Vector3 = (district_frame.x*tangent.x+district_frame.z*tangent.y).slide(n).normalized()
		# These existing CC0 meshes face +Z. A small yaw supplies a body stroke.
		var swim_basis: Basis = Basis(n.cross(forward).normalized(),n,forward)
		swim_basis = swim_basis*Basis(Vector3.UP,sin(time*5.0+phase)*.07)
		var scale_value: float = float(path.size)*float(fish.get_meta("size_factor",1.0))
		fish.transform = Transform3D(swim_basis.scaled(Vector3.ONE*scale_value),n*(radius+.055-float(path.depth)+.008*sin(time*.8+phase)))
